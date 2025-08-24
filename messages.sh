#!/bin/bash

# ===============================================================================
# macOS Messages Exporter Script
# ===============================================================================
#
# OVERVIEW:
# This script extracts messages and image attachments from the macOS Messages app 
# database and exports them to a JSON file with copied image files. It's designed 
# to help you backup or analyze your message history with a specific contact.
#
# WHAT IT DOES:
# 1. Takes two phone numbers as input (yours and the target contact's)
# 2. Validates the phone number formats are correct
# 3. Automatically installs required tools (Homebrew, sqlite3, jq) if missing
# 4. Connects to your Messages database (requires special permissions)
# 5. Searches for all messages and attachments between you and the target contact
# 6. Copies image attachments to a local directory
# 7. Exports the messages to a timestamped JSON file with attachment metadata
#
# REQUIREMENTS:
# - macOS with Messages app that has been used
# - Messages database copied to same directory as script (chat.db)
# - Internet connection (for automatic tool installation if needed)
#
# USAGE:
# ./messages.sh '+1234567890' '+0987654321'
#              ^your number    ^target number
#
# OUTPUT:
# Creates a file like "messages_1234567890.json" containing all messages
# between you and the target contact, with timestamps, sender information,
# and attachment metadata. Also creates an "attachments_1234567890/" directory
# containing copies of all image attachments from the conversation.
#
# PRIVACY NOTE:
# This script only reads your local Messages database and creates a local file.
# No data is sent anywhere or uploaded to any service.
# ===============================================================================

# Configure bash to exit immediately if any command fails, if we try to use
# an undefined variable, or if any command in a pipeline fails. This makes
# the script more robust and prevents it from continuing when something goes wrong.
set -euo pipefail

# ===============================================================================
# STEP 1: CHECK COMMAND LINE ARGUMENTS
# ===============================================================================
# This section ensures the user provided exactly two phone numbers when running
# the script. If they didn't, we show them how to use it correctly.

# Check if exactly two arguments (phone numbers) were provided
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <your_phone_number> <target_phone_number>"
  echo "Example: $0 '+18881234567' '+15559876543'"
  exit 1  # Exit with error code 1 to indicate incorrect usage
fi

# Store the command line arguments in clearly named variables
# $1 is the first argument (your phone number)
# $2 is the second argument (the target contact's phone number)
MY_NUMBER="$1"
TARGET_PHONE_NUMBER="$2"

# ===============================================================================
# STEP 2: VALIDATE PHONE NUMBER FORMAT
# ===============================================================================
# This section checks that both phone numbers are in the correct format.
# Phone numbers should start with + followed by 10-15 digits (country code + number).

# Validates phone number format according to international standards
#
# This function ensures phone numbers match the expected format used by Messages app.
# The validation checks for proper international format with country code.
#
# Parameters:
#   $1 (phone)     - The phone number string to validate
#   $2 (label)     - Descriptive label for error messages (e.g., "Your phone number")
#
# Returns:
#   0 - Phone number format is valid
#   1 - Phone number format is invalid
#
# Phone Number Format Requirements:
#   - Must start with '+' (plus sign)
#   - Must contain exactly 10-15 digits after the '+'
#   - No spaces, dashes, or other characters allowed
#   - Examples: +1234567890, +441234567890, +33123456789
#
validate_phone_number() {
  local phone="$1"      # The phone number to check
  local label="$2"      # A description (like "Your phone number") for error messages
  
  # Use a regular expression to check the format:
  # ^[+] = must start with a plus sign
  # [0-9]{10,15} = followed by exactly 10-15 digits
  # $ = must end there (no extra characters)
  if [[ ! "$phone" =~ ^[+][0-9]{10,15}$ ]]; then
    echo "Error: $label '$phone' is not a valid phone number format."
    echo "Expected format: +<country_code><phone_number> (10-15 digits total)"
    echo "Example: +18881234567"
    return 1  # Return error code to indicate validation failed
  fi
  return 0  # Return success code to indicate validation passed
}

# Check both phone numbers using our validation function
if ! validate_phone_number "$MY_NUMBER" "Your phone number"; then
  exit 1  # Exit if your phone number format is invalid
fi

if ! validate_phone_number "$TARGET_PHONE_NUMBER" "Target phone number"; then
  exit 1  # Exit if target phone number format is invalid
fi

# ===============================================================================
# STEP 3: INSTALL REQUIRED TOOLS
# ===============================================================================
# This section automatically installs the tools we need to extract and process
# the message data. We need 'sqlite3' to read the Messages database and 'jq'
# to format the output nicely.

# Installs Homebrew package manager for macOS
#
# Homebrew is required to install sqlite3 and jq dependencies. This function
# downloads and installs Homebrew from the official source, then configures
# the shell environment to make it available immediately.
#
# Architecture Detection:
#   - Apple Silicon (M1/M2/etc): Installs to /opt/homebrew/
#   - Intel Macs: Installs to /usr/local/
#
# Returns:
#   0 - Homebrew installed successfully and PATH configured
#   1 - Installation failed
#
# Side Effects:
#   - Downloads and executes the official Homebrew installer
#   - Modifies shell environment with brew shellenv
#   - Requires internet connection and admin privileges
#
install_homebrew() {
  echo "Homebrew not found. Installing Homebrew..."
  
  # Download and run the official Homebrew installer from GitHub
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo "Homebrew installed successfully."
    
    # Add Homebrew to the system PATH so we can use it immediately
    # Different Macs install Homebrew in different locations:
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
      # Apple Silicon Macs (M1, M2, etc.) use /opt/homebrew
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
      # Intel Macs use /usr/local
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    return 0  # Success
  else
    echo "Error: Failed to install Homebrew."
    return 1  # Failure
  fi
}

# Checks for command availability and installs via Homebrew if missing
#
# This function implements automatic dependency management by checking if a
# required command-line tool is available in PATH, and installing it through
# Homebrew if it's missing. Homebrew itself is installed if not present.
#
# Parameters:
#   $1 (cmd) - Name of the command to check and potentially install
#
# Returns:
#   0 - Command is available (either was installed or already present)
#   1 - Command could not be installed or Homebrew installation failed
#
# Process:
#   1. Check if command exists in PATH using 'command -v'
#   2. If missing, ensure Homebrew is available (install if needed)
#   3. Use 'brew install' to install the missing command
#   4. Report success/failure with visual indicators (✓/✗)
#
# Dependencies:
#   - install_homebrew() function for Homebrew installation
#   - Internet connection for downloading packages
#
check_and_install_dependency() {
  local cmd="$1"  # The name of the command we're checking for
  
  # Check if the command is already available on the system
  if command -v "$cmd" &> /dev/null; then
    echo "✓ $cmd is available"
    return 0  # Already installed, nothing to do
  fi
  
  echo "✗ $cmd not found, attempting to install..."
  
  # Before we can install tools, we need Homebrew
  if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew first..."
    if ! install_homebrew; then
      echo "Error: Cannot install $cmd without Homebrew."
      return 1  # Failed to install Homebrew
    fi
  fi
  
  # Now use Homebrew to install the missing tool
  echo "Installing $cmd via Homebrew..."
  if brew install "$cmd"; then
    echo "✓ $cmd installed successfully"
    return 0  # Installation successful
  else
    echo "✗ Failed to install $cmd"
    return 1  # Installation failed
  fi
}

# Check and install both tools we need
echo "Checking and installing dependencies..."
failed_deps=""  # Keep track of any tools that failed to install

# Try to install sqlite3 (database tool)
if ! check_and_install_dependency "sqlite3"; then
  failed_deps="$failed_deps sqlite3"  # Add to failed list
fi

# Try to install jq (JSON formatting tool)
if ! check_and_install_dependency "jq"; then
  failed_deps="$failed_deps jq"  # Add to failed list
fi

# If any tools failed to install, we can't continue
if [[ -n "$failed_deps" ]]; then
  echo "Error: Failed to install required dependencies:$failed_deps"
  echo "Please install them manually and try again."
  exit 1
fi

echo "All dependencies are ready!"

# Show the user what phone numbers we're working with
echo "Your number set to: ${MY_NUMBER}"
echo "Target number set to: ${TARGET_PHONE_NUMBER}"

# ===============================================================================
# STEP 4: LOCATE AND VALIDATE THE MESSAGES DATABASE
# ===============================================================================
# The Messages app stores all your messages in a special database file. We need
# to find this file and make sure we have permission to read it.

# The Messages database should be copied to the same directory as this script
SOURCE_DB_PATH="./chat.db"

# Check if the database file actually exists
if [[ ! -f "$SOURCE_DB_PATH" ]]; then
  echo "Error: Messages database not found at '$SOURCE_DB_PATH'"
  echo "Please copy your Messages database to this directory first:"
  echo "  cp ~/Library/Messages/chat.db ."
  echo ""
  echo "Note: You may need to quit the Messages app first before copying."
  exit 1
fi

# Check if we have permission to read the database file
if [[ ! -r "$SOURCE_DB_PATH" ]]; then
  echo "Error: Cannot read Messages database at '$SOURCE_DB_PATH'"
  echo "Please check file permissions on the copied database file."
  exit 1
fi

echo "Database found and accessible: $SOURCE_DB_PATH"

# ===============================================================================
# STEP 5: PREPARE THE OUTPUT FILE
# ===============================================================================
# Before we extract the messages, we need to decide where to save them and
# make sure we have permission to write the file.

# Create output directory structure based on the target phone number
# We remove the '+' symbol since it's not allowed in filenames on some systems
# Get the directory where this script is located to ensure files are created there
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR_NAME="$(echo "$TARGET_PHONE_NUMBER" | tr -d '+')"
TARGET_DIR="$SCRIPT_DIR/$TARGET_DIR_NAME"
SAFE_FILENAME="$TARGET_DIR/messages.json"
ATTACHMENTS_DIR="$TARGET_DIR/attachments"

# Check if the target directory already exists
if [[ -d "$TARGET_DIR" ]]; then
  echo "Warning: Output directory '$TARGET_DIR' already exists."
  # Ask the user if they want to overwrite it
  read -p "Overwrite? (y/N): " -r
  # If they don't type 'y' or 'Y', cancel the operation
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0  # Exit with success code since user chose to cancel
  fi
  # Remove existing directory to start fresh
  rm -rf "$TARGET_DIR"
fi

# Create the target directory
mkdir -p "$TARGET_DIR"
echo "Created output directory: $TARGET_DIR"

# Make sure we can write files in the script directory
if [[ ! -w "$SCRIPT_DIR" ]]; then
  echo "Error: Cannot write to script directory '$SCRIPT_DIR'"
  echo "Please ensure the script directory has write permissions."
  exit 1
fi

# ===============================================================================
# STEP 6: EXTRACT MESSAGES FROM DATABASE
# ===============================================================================
# This is where we actually read the Messages database and extract all the
# text messages between you and the target contact. We use SQL (database query
# language) to find and format the messages.

# This SQL query finds all messages between you and the target contact
# SQL is a language for asking questions about data in databases
SQL_QUERY="
SELECT
  -- Convert the timestamp to a human-readable date and time
  -- Messages stores dates as nanoseconds since Jan 1, 2001, so we need to convert
  datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') as timestamp,
  
  -- Figure out who sent each message: you or the other person
  -- If is_from_me = 1, it's from you; otherwise it's from the other person
  CASE WHEN message.is_from_me = 1 THEN '${MY_NUMBER}' ELSE handle.id END as sender,
  
  -- The actual message text
  message.text as message,
  
  -- Attachment information (if any)
  attachment.filename as attachment_filename,
  attachment.mime_type as attachment_mime_type,
  attachment.total_bytes as attachment_size,
  attachment.uti as attachment_uti,
  attachment.transfer_name as attachment_transfer_name
FROM
  -- Start with the chat table (contains conversation info)
  chat
  
  -- Connect to the message table through the join table
  -- (This is how the database links conversations to messages)
JOIN
  chat_message_join ON chat.ROWID = chat_message_join.chat_id
JOIN
  message ON chat_message_join.message_id = message.ROWID
  
  -- Connect to the handle table to get sender information
LEFT JOIN
  handle ON message.handle_id = handle.ROWID
  
  -- Connect to attachments (if any)
LEFT JOIN
  message_attachment_join ON message.ROWID = message_attachment_join.message_id
LEFT JOIN
  attachment ON message_attachment_join.attachment_id = attachment.ROWID
WHERE
  -- Only get messages from the conversation with our target phone number
  chat.chat_identifier = '${TARGET_PHONE_NUMBER}'
  
  -- Get messages with text OR attachments
  AND (message.text IS NOT NULL OR attachment.ROWID IS NOT NULL)
ORDER BY
  -- Sort messages by date, oldest first
  message.date ASC;
"

echo "Querying database for messages between you and ${TARGET_PHONE_NUMBER}..."

# Run the database query and capture both the output and any error messages
if ! query_result=$(sqlite3 -json "${SOURCE_DB_PATH}" "${SQL_QUERY}" 2>&1); then
  echo "Error: Database query failed:"
  echo "$query_result"
  echo ""
  echo "Possible causes:"
  echo "  1. Database file is corrupted"
  echo "  2. No conversation exists with phone number '${TARGET_PHONE_NUMBER}'"
  echo "  3. Phone number format doesn't match what's stored in Messages"
  exit 1
fi

# ===============================================================================
# STEP 6.5: COPY ATTACHMENT FILES
# ===============================================================================
# If we found any attachments, copy the image files to preserve them
#
# This section handles attachment preservation by:
# 1. Checking if any messages contain attachments
# 2. Creating a dedicated attachments directory
# 3. Copying each unique attachment file with duplicate handling
# 4. Expanding tilde (~) paths to full home directory paths
# 5. Providing feedback on copy success/failure

# Create attachments directory if we have any attachments
# Use jq to check if any messages in the result have attachment_filename set
if echo "$query_result" | jq -e 'any(.[]; .attachment_filename)' >/dev/null 2>&1; then
  echo "Found attachments, creating directory: $ATTACHMENTS_DIR"
  mkdir -p "$ATTACHMENTS_DIR"
  
  # Extract unique attachment filenames and process each one
  # Pipeline explanation:
  # 1. Parse JSON and select messages with attachments
  # 2. Extract attachment_filename field 
  # 3. Sort and remove duplicates with 'sort -u'
  # 4. Process each filename in the while loop
  echo "$query_result" | jq -r '.[] | select(.attachment_filename != null) | .attachment_filename' | sort -u | while IFS= read -r attachment_path; do
    # Expand ~ to full home directory path using parameter expansion
    # ${attachment_path/#\~/$HOME} replaces leading ~ with $HOME value
    expanded_path="${attachment_path/#\~/$HOME}"
    
    # Only process if path exists and is a regular file
    if [[ -n "$expanded_path" && -f "$expanded_path" ]]; then
      # Extract just the filename from the full path
      attachment_basename=$(basename "$expanded_path")
      echo "Copying attachment: $attachment_basename"
      
      # Handle filename conflicts by adding numeric suffixes
      # This prevents overwriting files with identical names
      counter=1
      target_path="$ATTACHMENTS_DIR/$attachment_basename"
      
      # Find an available filename by incrementing counter
      while [[ -f "$target_path" ]]; do
        # Parse filename and extension for proper suffix insertion
        filename_without_ext="${attachment_basename%.*}"    # Remove last .extension
        extension="${attachment_basename##*.}"              # Extract last .extension
        
        if [[ "$filename_without_ext" == "$extension" ]]; then
          # No extension detected (filename_without_ext equals extension)
          target_path="$ATTACHMENTS_DIR/${attachment_basename}_${counter}"
        else
          # Extension detected, insert counter before extension
          target_path="$ATTACHMENTS_DIR/${filename_without_ext}_${counter}.${extension}"
        fi
        ((counter++))  # Increment counter for next iteration
      done
      
      # Attempt to copy file with error suppression, report result
      if cp "$expanded_path" "$target_path" 2>/dev/null; then
        echo "✓ Copied: $attachment_basename"
      else
        echo "✗ Failed to copy: $attachment_basename (file may not exist or no permission)"
      fi
    fi
  done
fi

# ===============================================================================
# STEP 7: PROCESS AND ENHANCE JSON OUTPUT
# ===============================================================================
# Update attachment paths in JSON to point to our copied files and format nicely

echo "Processing and formatting results..."

# Use 'jq' to format the query results, update attachment paths, and save to file
if ! echo "$query_result" | jq --arg attachments_dir "attachments" '
  map(
    if .attachment_filename != null then
      . + {
        "attachment_local_path": ($attachments_dir + "/" + (.attachment_filename | split("/") | last)),
        "has_attachment": true
      }
    else
      . + {"has_attachment": false}
    end
  )
' > "${SAFE_FILENAME}" 2>/dev/null; then
  echo "Error: Failed to process query results with jq"
  echo "Raw query output:"
  echo "$query_result"
  exit 1
fi

# ===============================================================================
# STEP 8: GENERATE HTML CONVERSATION VIEW
# ===============================================================================
# Create a nicely formatted HTML file showing the conversation thread

# Generates an HTML conversation view from the exported JSON data
#
# This function creates a user-friendly HTML file that displays the message
# conversation in a chat-like interface similar to the Messages app. The HTML
# includes CSS styling, JavaScript for image viewing, and organized message layout.
#
# Parameters:
#   $1 (json_file)     - Path to the input JSON file containing message data
#   $2 (html_file)     - Path where the generated HTML file should be saved
#   $3 (my_number)     - Your phone number (for message attribution)
#   $4 (target_number) - Target contact's phone number
#
# Generated HTML Features:
#   - Messages app-like visual styling with blue/gray message bubbles
#   - Conversation statistics (total messages, attachments, date range)
#   - Date dividers to organize messages chronologically
#   - Interactive image viewing with modal overlay
#   - Responsive design for desktop and mobile viewing
#   - Proper HTML escaping for message content security
#
# Technical Implementation:
#   - Uses jq for JSON parsing and HTML generation
#   - Implements proper HTML entity escaping (&, <, >, ")
#   - Handles image attachments vs. other file types differently
#   - Groups messages by date with automatic divider insertion
#   - Includes embedded CSS and JavaScript for self-contained file
#
generate_html_conversation() {
  local json_file="$1"
  local html_file="$2"
  local my_number="$3"
  local target_number="$4"
  
  echo "Generating HTML conversation view..."
  
  # Use a single jq command to generate the entire HTML content
  jq -r --arg my_number "$my_number" --arg target_number "$target_number" '
    # Calculate stats once
    (length) as $total_messages |
    ([.[] | select(.has_attachment == true)] | length) as $attachment_count |
    (if $total_messages > 0 then (.[0].timestamp | split(" ")[0]) else "" end) as $first_date |
    (if $total_messages > 0 then (.[-1].timestamp | split(" ")[0]) else "" end) as $last_date |
    
    # Generate complete HTML
    "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Messages Conversation</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
            line-height: 1.4;
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding: 20px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .conversation {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        
        .message {
            display: flex;
            margin-bottom: 10px;
        }
        
        .message.sent {
            justify-content: flex-end;
        }
        
        .message.received {
            justify-content: flex-start;
        }
        
        .message-bubble {
            max-width: 70%;
            padding: 12px 16px;
            border-radius: 18px;
            position: relative;
            word-wrap: break-word;
        }
        
        .message.sent .message-bubble {
            background-color: #007AFF;
            color: white;
            border-bottom-right-radius: 4px;
        }
        
        .message.received .message-bubble {
            background-color: #E9E9EB;
            color: black;
            border-bottom-left-radius: 4px;
        }
        
        .timestamp {
            font-size: 11px;
            color: #666;
            margin-top: 4px;
            text-align: center;
        }
        
        .attachment {
            margin-top: 8px;
        }
        
        .attachment img {
            max-width: 250px;
            max-height: 250px;
            border-radius: 10px;
            cursor: pointer;
            transition: transform 0.2s;
        }
        
        .attachment img:hover {
            transform: scale(1.05);
        }
        
        .attachment-info {
            font-size: 12px;
            color: #666;
            margin-top: 4px;
        }
        
        .date-divider {
            text-align: center;
            margin: 20px 0;
            color: #666;
            font-size: 12px;
            font-weight: bold;
        }
        
        .stats {
            background: white;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .modal {
            display: none;
            position: fixed;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0,0,0,0.9);
        }
        
        .modal-content {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            max-width: 90%;
            max-height: 90%;
        }
        
        .close {
            position: absolute;
            top: 15px;
            right: 35px;
            color: #f1f1f1;
            font-size: 40px;
            font-weight: bold;
            cursor: pointer;
        }
        
        .close:hover {
            color: #bbb;
        }
    </style>
</head>
<body>
    <div class=\"header\">
        <h1>Messages Conversation</h1>
        <p><strong>Between:</strong> \($my_number) and \($target_number)</p>
    </div>
    
    <div class=\"stats\">
        <p><strong>Total Messages:</strong> \($total_messages)</p>
        <p><strong>Messages with Attachments:</strong> \($attachment_count)</p>
        <p><strong>Date Range:</strong> \($first_date) - \($last_date)</p>
    </div>
    
    <div class=\"conversation\">" +
    
    # Generate messages with date dividers
    (. as $messages | 
     reduce range(0; length) as $i (""; 
       . + 
       ($messages[$i] | 
         (.timestamp | split(" ")[0]) as $current_date |
         (.timestamp | split(" ")[1] | split(":")[0:2] | join(":")) as $time_only |
         (if .sender == $my_number then "sent" else "received" end) as $message_class |
         (.message // "" | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;")) as $escaped_message |
         (if (.attachment_filename // "") | test("\\.(jpg|jpeg|png|gif|bmp|webp)$"; "i") then "image" else "file" end) as $attachment_type |
         
         # Add date divider if this is the first message or date changed from previous
         (if $i == 0 or ($messages[$i-1].timestamp | split(" ")[0]) != $current_date then
            "        <div class=\"date-divider\">\($current_date)</div>\n"
          else "" 
          end) +
         
         # Generate message HTML
         "        <div class=\"message \($message_class)\">\n" +
         "            <div class=\"message-bubble\">\n" +
         (if $escaped_message != "" then 
            "                <div>\($escaped_message)</div>\n" 
          else "" 
          end) +
         (if .has_attachment == true and (.attachment_local_path // "") != "" then
            "                <div class=\"attachment\">\n" +
            (if $attachment_type == "image" then
               "                    <img src=\"\(.attachment_local_path)\" alt=\"Attachment\" onclick=\"showModal('\''\(.attachment_local_path)'\'')\">\n"
             else
               "                    <div class=\"attachment-info\">📎 \(.attachment_filename // "Unknown")</div>\n"
             end) +
            "                </div>\n"
          else ""
          end) +
         "                <div class=\"timestamp\">\($time_only)</div>\n" +
         "            </div>\n" +
         "        </div>\n"
       )
     )
    ) +
    
    "    </div>
    
    <!-- Modal for viewing images -->
    <div id=\"image-modal\" class=\"modal\">
        <span class=\"close\" onclick=\"closeModal()\">&times;</span>
        <img class=\"modal-content\" id=\"modal-image\">
    </div>
    
    <script>
        function showModal(imageSrc) {
            document.getElementById('modal-image').src = imageSrc;
            document.getElementById('image-modal').style.display = 'block';
        }
        
        function closeModal() {
            document.getElementById('image-modal').style.display = 'none';
        }
        
        window.onclick = function(event) {
            const modal = document.getElementById('image-modal');
            if (event.target === modal) {
                modal.style.display = 'none';
            }
        }
    </script>
</body>
</html>"
  ' "$json_file" > "$html_file"

  echo "HTML conversation view created: $html_file"
}

# ===============================================================================
# STEP 9: VERIFY AND REPORT RESULTS
# ===============================================================================
# Check if we actually found any messages and let the user know what happened.

# Check if the output file has any content
if [[ ! -s "$SAFE_FILENAME" ]]; then
  echo "Warning: Output file 'messages.json' is empty."
  echo "This likely means no messages were found for phone number '${TARGET_PHONE_NUMBER}'"
  echo ""
  echo "Tips:"
  echo "  1. Make sure the phone number format matches exactly what's in Messages"
  echo "  2. Check if you have any conversation with this number"
  echo "  3. Try running without the '+' prefix (e.g., '18881234567')"
else
  # Count how many messages we found using jq
  message_count=$(jq length "$SAFE_FILENAME" 2>/dev/null || echo "unknown")
  attachment_count=$(jq '[.[] | select(.has_attachment == true)] | length' "$SAFE_FILENAME" 2>/dev/null || echo "0")
  
  # Generate HTML conversation view
  HTML_FILENAME="$TARGET_DIR/messages.html"
  generate_html_conversation "$SAFE_FILENAME" "$HTML_FILENAME" "$MY_NUMBER" "$TARGET_PHONE_NUMBER"
  
  echo "Success! Found $message_count messages."
  if [[ "$attachment_count" -gt 0 ]]; then
    echo "Found $attachment_count messages with attachments."
    echo "Attachments copied to: ${TARGET_DIR}/attachments/"
  fi
  echo "Output saved to: ${SAFE_FILENAME}"
  echo "HTML conversation view: ${HTML_FILENAME}"
  echo "All files organized in directory: ${TARGET_DIR}"
  echo ""
  echo "The messages.json file contains JSON data with timestamps, senders, message text, and attachment info."
  echo "The messages.html file provides a nicely formatted conversation view that you can open in any web browser."
  if [[ "$attachment_count" -gt 0 ]]; then
    echo "Image attachments have been copied to the 'attachments' subdirectory and are viewable in the HTML file."
  fi
fi