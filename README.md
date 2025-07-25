# Job Email Tracker

An intelligent job application tracker that uses Claude AI to analyze your emails and maintain a comprehensive CSV database of your job applications, interviews, and follow-ups.

## Overview

This tool automatically:
- Extracts emails from Apple Mail using AppleScript
- Analyzes email content with Claude AI to identify job-related communications
- Tracks application status, company information, and required actions
- Maintains a CSV database with deduplication and status updates
- Provides actionable insights for interview follow-ups

## Prerequisites

- **macOS** with Apple Mail configured
- **Nushell** (`nu` command available)
- **Anthropic API Key** for Claude AI analysis
- **Mail access permissions** for AppleScript

## Setup

1. **Install Nushell**:
   ```bash
   brew install nushell
   ```

2. **Set your Anthropic API key**:
   ```bash
   export ANTHROPIC_API_KEY="your-api-key-here"
   # Add to ~/.zshrc for persistence
   echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.zshrc
   ```

3. **Grant Mail access** when prompted by macOS

## Usage

### First Run (Full Analysis)
```bash
# Analyze last 14 days of emails
nu job_tracker.nu --days 14
```

### Daily Monitoring
```bash
# Check yesterday's emails only
nu job_tracker.nu --days 1
```

### Skip Email Extraction (Use Existing Data)
```bash
# Process existing email_data_clean.json
nu job_tracker.nu --skip-extraction
```

### Performance Options
```bash
# Faster processing with larger batches
nu job_tracker.nu --days 7 --batch-size 20

# Custom output file
nu job_tracker.nu --days 7 --output my_applications.csv
```

## Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--days` | 7 | Number of days back to scan emails |
| `--output` | `job_applications.csv` | Output CSV filename |
| `--email-json` | `email_data_clean.json` | Email data file from AppleScript |
| `--batch-size` | 1 | Emails per Claude API call (1-20) |
| `--skip-extraction` | false | Skip email extraction, use existing JSON |

## Output Files

### `job_applications.csv`
Main tracking database with columns:
- `message_id` - Unique email identifier
- `company_name` - Extracted company name
- `job_title` - Position title
- `application_status` - Current status (Applied, Interview Scheduled, Rejected, etc.)
- `confidence_score` - AI confidence (0.0-1.0)
- `key_details` - Important information summary
- `next_action` - Recommended follow-up action
- `last_contact` - Last communication date
- `created_at` / `updated_at` - Tracking timestamps

### `email_data_clean.json`
Temporary file containing extracted email data (gets overwritten each run)

## Key Features

### Smart Deduplication
- Prevents duplicate entries for the same company + job title
- Updates existing records with latest information
- Preserves historical data while tracking status changes

### AI-Powered Analysis
- Uses Claude 3.5 Haiku for cost-effective analysis
- Extracts company names, job titles, and application status
- Identifies required follow-up actions
- Confidence scoring for data quality assessment

### Status Tracking
Common status values:
- `Applied` - Application submitted
- `Interview Scheduled` - Interview arranged
- `Interview Completed` - Awaiting feedback
- `Under Review` - Application being reviewed
- `Rejected` - Application unsuccessful
- `Offer Received` - Job offer received

## Daily Workflow

```bash
# Morning routine - check yesterday's job emails
source ~/.zshrc  # Load API key
nu job_tracker.nu --days 1 --batch-size 10

# Review follow-ups needed
grep -i "interview\|call\|follow" job_applications.csv

# Weekly catch-up
nu job_tracker.nu --days 7 --batch-size 20
```

## Data Safety

✅ **CSV data is safe**: Always merges with existing data, never overwrites
✅ **Historical tracking**: Maintains full application history
✅ **Status updates**: Updates existing applications with latest information

⚠️ **JSON gets overwritten**: `email_data.json` is recreated each run with new date range

## Performance Tips

- **Batch size**: Use `--batch-size 10-20` for faster processing
- **Skip extraction**: Use `--skip-extraction` when re-processing same emails
- **Daily runs**: Process 1 day at a time to minimize API usage
- **API costs**: ~$0.50-2.00 per 600 emails with Claude Haiku

## Troubleshooting

### Permission Issues
```bash
# Grant Mail access in System Preferences > Privacy & Security
# Re-run the script after granting permissions
```

### API Errors
```bash
# Verify API key
echo $ANTHROPIC_API_KEY

# Re-source shell configuration
source ~/.zshrc
```

### Parsing Failures
```bash
# Use smaller batch sizes
nu job_tracker.nu --days 7 --batch-size 1

# Check for UTF-8 issues (handled automatically)
```

## Example Output

```
🔍 Processing job application emails from last 7 days with LLM...
📧 Extracting emails with AppleScript...
Found 156 total emails
🤖 Processing 156 emails with LLM in batches of 5...
✅ Identified 23 job-related emails out of 156 total
📂 Loading existing data from job_applications.csv
📈 Adding 8 new job applications
🔄 Skipping 15 duplicates
💾 Saved 95 total job applications to job_applications.csv

📊 Job Application Summary:
==========================
Total Applications: 95

📈 By Status:
  Applied: 45
  Under Review: 18
  Interview Scheduled: 5
  Rejected: 20
  Offer Received: 2

🎯 High Confidence Applications:
TechCorp    Software Engineer    Interview Scheduled    0.95
StartupXYZ  Python Developer     Applied               0.92
BigTech     Senior Engineer      Under Review          0.90

⚡ Next Actions Needed:
TechCorp           Prepare for technical interview tomorrow
StartupXYZ         Follow up on application status
ConsultingFirm     Schedule call with recruiter
```

## Sample CSV Output

```csv
message_id,company_name,job_title,application_status,confidence_score,key_details,next_action
12345,TechCorp,Software Engineer,Interview Scheduled,0.95,Technical interview on Friday 2pm,Prepare coding examples
12346,StartupXYZ,Python Developer,Applied,0.92,Application submitted via LinkedIn,Follow up in 1 week
12347,BigTech,Senior Engineer,Under Review,0.90,Application under review by hiring team,Wait for response
```

## Contributing

This tool is designed for personal job tracking. Modify the analysis prompt in `create_llm_prompt()` to customize the AI analysis for your specific needs.

## License

Personal use tool. Ensure your Anthropic API usage complies with their terms of service.