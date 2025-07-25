#!/usr/bin/env nu

# LLM-Powered Job Application Email Tracker
# Uses Claude via API to intelligently parse emails and maintain job applications CSV

def main [
    --days: int = 7           # Days back to scan emails
    --output: string = "job_applications.csv"  # Output CSV file
    --email-json: string = "email_data_clean.json"  # Email JSON from AppleScript
    --batch-size: int = 1     # Number of emails to process per LLM call
    --skip-extraction         # Skip email extraction if JSON already exists
] {
    print $"🔍 Processing job application emails from last ($days) days with LLM..."
    
    # Step 1: Run AppleScript to extract emails (unless skipped)
    if not $skip_extraction {
        print "📧 Extracting emails with AppleScript..."
        let script_result = (osascript EmailExtractor.scpt $days $email_json)
        print $script_result
    } else {
        if ($email_json | path exists) {
            print $"📧 Skipping extraction - using existing ($email_json)"
        } else {
            print $"❌ Error: ($email_json) not found. Run without --skip-extraction first."
            return
        }
    }
    
    # Step 2: Load email data
    print "📊 Loading email data..."
    let email_data = try {
        open $email_json | from json
    } catch {
        print "⚠️  JSON contains non-UTF8 characters, attempting to clean..."
        open --raw $email_json | decode utf-8 | from json
    }
    print $"Found ($email_data | length) total emails"
    
    # Step 3: Process emails in batches with LLM
    let job_applications = (process_emails_with_llm $email_data $batch_size)
    
    # Step 4: Load existing CSV or create new structure
    let existing_data = if ($output | path exists) {
        print $"📂 Loading existing data from ($output)"
        let loaded_data = (open $output)
        if ($loaded_data | length) > 0 {
            $loaded_data
        } else {
            create_empty_job_csv
        }
    } else {
        print $"📝 Creating new tracking file: ($output)"
        create_empty_job_csv
    }
    
    # Step 5: Merge and deduplicate
    let updated_data = (merge_job_applications $existing_data $job_applications)
    
    # Step 6: Save results
    $updated_data 
    | sort-by date_received 
    | reverse
    | save --force $output
    
    print $"💾 Saved ($updated_data | length) total job applications to ($output)"
    
    # Step 7: Show summary
    show_job_summary $updated_data
}

# Process emails in batches using LLM
def process_emails_with_llm [emails, batch_size] {
    let total_emails = ($emails | length)
    print $"🤖 Processing ($total_emails) emails with LLM in batches of ($batch_size)..."
    
    mut all_job_applications = []
    mut processed = 0
    
    # Process in batches to avoid token limits
    for batch in ($emails | group $batch_size) {
        print $"Processing batch: ($processed + 1) to ($processed + ($batch | length))..."
        
        let batch_result = (send_batch_to_llm $batch)
        $all_job_applications = ($all_job_applications | append $batch_result)
        $processed = $processed + ($batch | length)
        
        # Small delay to be respectful to API and avoid rate limits
        sleep 2sec
    }
    
    # Filter out non-job emails
    let job_emails = ($all_job_applications | where is_job_related == true)
    print $"✅ Identified ($job_emails | length) job-related emails out of ($total_emails) total"
    
    $job_emails
}

# Send a batch of emails to LLM for processing
def send_batch_to_llm [email_batch] {
    # Trim email content to reduce size
    let trimmed_batch = ($email_batch | each { |email|
        {
            messageId: $email.messageId,
            subject: $email.subject,
            sender: $email.sender,
            dateReceived: $email.dateReceived,
            content: ($email.content | str substring 0..1000)
        }
    })
    let prompt = (create_llm_prompt $trimmed_batch)
    
    # Call Claude API (you'll need to set ANTHROPIC_API_KEY)
    let request_body = {
        "model": "claude-3-5-haiku-20241022",
        "max_tokens": 8000,
        "messages": [
            {
                "role": "user", 
                "content": $prompt
            }
        ]
    }
    
    # Check if API key is available
    let api_key = ($env | get -o ANTHROPIC_API_KEY)
    if ($api_key | is-empty) {
        print "❌ Error: ANTHROPIC_API_KEY environment variable not set"
        print "Please run: export ANTHROPIC_API_KEY=\"your-key-here\""
        return []
    }
    
    let json_body = ($request_body | to json)
    
    let response = try {
        ($json_body | http post "https://api.anthropic.com/v1/messages" 
        --headers {
            "x-api-key": $env.ANTHROPIC_API_KEY,
            "content-type": "application/json",
            "anthropic-version": "2023-06-01"
        })
    } catch { |err|
        print $"❌ API request failed: ($err)"
        return []
    }
    
    # Parse the JSON response from Claude
    let claude_response = ($response | get content.0.text)
    
    try {
        let parsed = ($claude_response | from json)
        # Convert single object to array for consistency
        if ($parsed | describe) == "record" {
            [$parsed]
        } else {
            $parsed
        }
    } catch {
        print $"⚠️  Failed to parse LLM response, skipping batch"
        print $"Response preview: ($claude_response | str substring 0..200)"
        []
    }
}

# Create the prompt for LLM processing
def create_llm_prompt [emails] {
    let emails_json = ($emails | to json)
    
"JSON only: {\"message_id\":\"id\",\"is_job_related\":true/false,\"company_name\":\"company\",\"job_title\":\"job\",\"application_status\":\"status\",\"confidence_score\":0.9,\"key_details\":\"brief\",\"next_action\":\"action\"}

Email: " + $emails_json
}

# Create empty job CSV structure
def create_empty_job_csv [] {
    [{
        message_id: "",
        company_name: "",
        job_title: "",
        application_status: "",
        date_received: "",
        date_applied: "",
        last_contact: "",
        next_action: "",
        key_details: "",
        confidence_score: 0.0,
        email_subject: "",
        sender: "",
        created_at: "",
        updated_at: ""
    }] | first 0  # Empty table with correct schema
}

# Merge new job applications with existing data
def merge_job_applications [existing, new_applications] {
    let existing_ids = ($existing | get message_id? | default [])
    
    # Create unique keys for existing records (company + job_title)
    let existing_keys = ($existing | each {|rec| 
        $"($rec.company_name | default 'Unknown')_($rec.job_title | default 'Not Specified')"
    })
    
    # Convert LLM results to our CSV format, checking for company+job duplicates
    let formatted_new = (
        $new_applications 
        | where message_id not-in $existing_ids
        | each {|app| 
            let app_key = $"($app.company_name | default 'Unknown')_($app.job_title | default 'Not Specified')"
            {app: $app, key: $app_key, is_duplicate: ($app_key in $existing_keys)}
        }
        | where is_duplicate == false
        | get app
        | each {|app| format_job_application $app}
    )
    
    print $"📈 Adding ($formatted_new | length) new job applications"
    print $"🔄 Skipping (($new_applications | length) - ($formatted_new | length)) duplicates"
    
    # Update existing records with new information from same company+job
    let updated_existing = (
        $existing 
        | each {|existing_app|
            let existing_key = $"($existing_app.company_name | default 'Unknown')_($existing_app.job_title | default 'Not Specified')"
            let matching_records = ($new_applications | where {|app|
                let app_key = $"($app.company_name | default 'Unknown')_($app.job_title | default 'Not Specified')"
                $app_key == $existing_key
            })
            let matching_new = if ($matching_records | length) > 0 {
                $matching_records | first
            } else {
                null
            }
            
            if ($matching_new != null) {
                # Update with new information (always take latest info)
                let updated_app = (format_job_application $matching_new)
                {
                    message_id: $existing_app.message_id,  # Keep original message_id
                    company_name: $updated_app.company_name,
                    job_title: $updated_app.job_title,
                    application_status: $updated_app.application_status,  # Update status
                    date_received: $existing_app.date_received,
                    date_applied: $existing_app.date_applied,
                    last_contact: $updated_app.created_at,  # Update last contact
                    next_action: $updated_app.next_action,  # Update next action
                    key_details: $updated_app.key_details,  # Latest details
                    confidence_score: ($updated_app.confidence_score | if $in > ($existing_app.confidence_score | default 0.0) { $in } else { $existing_app.confidence_score }),
                    email_subject: $existing_app.email_subject,
                    sender: $existing_app.sender,
                    created_at: $existing_app.created_at,  # Keep original created date
                    updated_at: $updated_app.created_at    # Update timestamp
                }
            } else {
                $existing_app
            }
        }
    )
    
    $updated_existing | append $formatted_new
}

# Format LLM response into our CSV structure
def format_job_application [llm_app] {
    let now = (date now | format date "%Y-%m-%d %H:%M:%S")
    
    {
        message_id: ($llm_app.message_id | to text),
        company_name: ($llm_app.company_name | default "Unknown" | to text),
        job_title: ($llm_app.job_title | default "Not Specified" | to text),
        application_status: ($llm_app.application_status | default "" | to text),
        date_received: "", # Will be filled from original email data
        date_applied: "",
        last_contact: $now,
        next_action: ($llm_app.next_action | default "" | to text),
        key_details: ($llm_app.key_details | default "" | to text),
        confidence_score: ($llm_app.confidence_score | default 0.0),
        email_subject: "",  # Will be filled from original email data
        sender: "",  # Will be filled from original email data
        created_at: $now,
        updated_at: $now
    }
}

# Show summary of job applications
def show_job_summary [data] {
    print "\n📊 Job Application Summary:"
    print "=========================="
    
    let total = ($data | length)
    print $"Total Applications: ($total)"
    
    if ($total > 0) {
        print "\n📈 By Status:"
        $data 
        | group-by application_status 
        | transpose status count 
        | each {|row| $"  ($row.status): ($row.count | length)"}
        | str join "\n"
        | print
        
        print "\n🏢 By Company:"
        $data 
        | group-by company_name 
        | transpose company count 
        | sort-by count 
        | reverse 
        | first 10
        | each {|row| $"  ($row.company): ($row.count | length)"}
        | str join "\n"
        | print
        
        print "\n🎯 High Confidence Applications:"
        $data 
        | where confidence_score > 0.8
        | select company_name job_title application_status confidence_score
        | first 5
        | table
        | print
        
        print "\n⚡ Next Actions Needed:"
        $data 
        | where next_action != ""
        | select company_name next_action
        | first 5
        | table
        | print
    }
}

# Helper function to group items into batches
def group [size] {
    let input = $in
    let total = ($input | length)
    mut result = []
    mut i = 0
    
    while $i < $total {
        let batch = ($input | skip $i | first $size)
        $result = ($result | append [$batch])
        $i = $i + $size
    }
    
    $result
}
