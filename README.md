# macOS Messages Exporter

A comprehensive tool for extracting messages and attachments from the macOS Messages app database, creating organized backups with both JSON data and HTML conversation views.

## 🌟 Features

- **Complete Message Export**: Extracts all text messages between you and a specific contact
- **Attachment Handling**: Automatically copies and organizes image attachments
- **Multiple Output Formats**: Generates both machine-readable JSON and human-friendly HTML
- **Automatic Setup**: Installs required dependencies (Homebrew, sqlite3, jq) automatically
- **Organized Storage**: Creates timestamped directories to keep exports organized
- **Privacy Focused**: Everything stays local - no data is uploaded or shared

## 📋 Requirements

- macOS with Messages app
- Messages database access (requires copying the database file)
- Terminal/command line access
- Internet connection (for automatic dependency installation)

## 🚀 Quick Start

### 1. Copy the Messages Database

**Important**: Quit the Messages app first, then copy the database:

```bash
# Quit Messages app, then copy the database
cp ~/Library/Messages/chat.db .
```

> **Note**: The database file can be several gigabytes depending on your message history.

### 2. Make Script Executable

```bash
chmod +x messages.sh
```

### 3. Run the Script

```bash
./messages.sh '+1234567890' '+0987654321'
#              ^your number    ^target contact's number
```

That's it! The script will handle dependency installation automatically.

## 📖 Detailed Setup

### Manual Dependency Installation (Optional)

If you prefer to install dependencies manually:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install sqlite jq
```

### Phone Number Format

Phone numbers must be in international format:

- **Format**: `+<country_code><phone_number>`
- **Length**: 10-15 digits total
- **Examples**:
  - US: `+1234567890`
  - UK: `+441234567890`
  - International: `+33123456789`

## 📁 Output Structure

The script creates a organized directory structure:

```text
<target_phone_number>/
├── messages.json          # Raw JSON data
├── messages.html         # Formatted conversation view
└── attachments/          # Copied image files (if any)
    ├── image1.jpg
    ├── image2.png
    └── ...
```

### JSON Format

Each message object contains:

```json
{
  "timestamp": "2024-01-15 10:30:45",
  "sender": "+1234567890", 
  "message": "Hello there!",
  "attachment_filename": "~/Library/Messages/Attachments/ab/12/photo.jpg",
  "attachment_local_path": "attachments/photo.jpg",
  "attachment_mime_type": "image/jpeg",
  "attachment_size": 245760,
  "has_attachment": true
}
```

### HTML Conversation View

The HTML file provides:

- **Styled Interface**: Messages app-like appearance
- **Conversation Stats**: Message count, date range, attachment summary
- **Image Viewing**: Click to view images in full size
- **Date Organization**: Messages grouped by date
- **Responsive Design**: Works on desktop and mobile browsers

## 🔧 Troubleshooting

### Database Issues

| Problem | Solution |
|---------|----------|
| "Messages database not found" | Copy database: `cp ~/Library/Messages/chat.db .` |
| "Cannot read database" | Quit Messages app before copying |
| Database file missing | Check file exists: `ls -la chat.db` |

### Message Extraction Issues  

| Problem | Solution |
|---------|----------|
| "No messages found" | Verify phone number format matches Messages |
| Empty results | Try without `+` prefix: `1234567890` |
| Wrong contact | Check you have a conversation with that number |

### Installation Issues

| Problem | Solution |
|---------|----------|
| Homebrew installation fails | Install manually from [brew.sh](https://brew.sh/) |
| Tool installation fails | Run `brew install sqlite jq` separately |
| Permission errors | Check Terminal has full disk access |

### Storage Issues

| Problem | Solution |
|---------|----------|
| "No space left" | Database can be 3-10GB+ depending on history |
| Slow copying | Use external drive for large databases |
| Temporary files | `chat.db-shm` and `chat.db-wal` are normal SQLite files |

## 🔒 Privacy & Security

- **100% Local**: All processing happens on your machine
- **No Network**: No data is transmitted to external servers  
- **No Logging**: Script doesn't create logs of your messages
- **No Persistence**: Temporary files are cleaned up automatically
- **Source Available**: Full script source code is readable and auditable

## 📊 Understanding the Database

The Messages database contains:

- **chat**: Conversation metadata
- **message**: Individual message content and timestamps
- **handle**: Contact information and phone numbers
- **attachment**: File attachments and metadata
- **Various joins**: Link messages to conversations and attachments

The script uses SQL queries to extract and correlate this data into a readable format.

## 🗂️ File Management

### Created Files

- `<phone_number>/messages.json`: Raw message data
- `<phone_number>/messages.html`: Conversation view
- `<phone_number>/attachments/`: Image copies

### SQLite Working Files

- `chat.db-shm`: Shared memory coordination
- `chat.db-wal`: Write-ahead logging

> These `.shm` and `.wal` files are temporary SQLite working files and can be safely deleted after the script completes.

## 🤝 Contributing

Found a bug or want to suggest improvements? Feel free to:

- Report issues with the script behavior
- Suggest additional export formats
- Recommend UI improvements for the HTML output
- Share compatibility updates for new macOS versions

## 📄 License

This script is provided as-is for personal use. Please respect privacy laws and only export your own message data.
