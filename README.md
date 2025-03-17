# audiobook-automator

a command-line tool for automatically processing audiobook files:
- extracts metadata from filenames, id3 tags, and online sources
- detects chapters from multiple audio files
- creates chaptered m4b files with correct metadata
- organizes files into a structured library

## features

- **smart metadata extraction**: pulls author, title, series, narrator info from filenames and tags
- **online metadata lookup**: finds missing info from goodreads and librivox
- **automatic genre detection**: categorizes books based on metadata
- **smart organization**: creates a well-structured library sorted by genre, author, and series
- **chapter detection**: automatically creates chapter markers from individual files
- **cover art handling**: finds or downloads cover art and embeds it in the audiobook file
- **cross-platform support**: works on macos, linux, and windows (via wsl)

## requirements

- ffmpeg (for audio processing)
- mp4v2 (for m4b file generation)
- fd (for file finding)
- jq (for json processing)
- mediainfo (for media file analysis)
- python3 (for online metadata lookup)
- python packages: requests, beautifulsoup4, fuzzywuzzy, python-Levenshtein

## installation

### easy installation (recommended)

run the installation script:

```bash
./install_prerequisites.sh
```

this will automatically detect your os and install all required dependencies.

### manual installation

#### macos

```bash
# install homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# install required tools
brew install ffmpeg mp4v2 fd jq mediainfo python3

# install python packages
pip3 install requests beautifulsoup4 fuzzywuzzy python-Levenshtein
```

#### linux (debian/ubuntu)

```bash
# update package list
sudo apt-get update

# install required tools
sudo apt-get install ffmpeg mp4v2-utils fd-find jq mediainfo python3 python3-pip

# create alias for fd (debian/ubuntu calls it fd-find)
echo 'alias fd=fdfind' >> ~/.bashrc
source ~/.bashrc

# install python packages
pip3 install requests beautifulsoup4 fuzzywuzzy python-Levenshtein
```

#### windows (wsl)

1. install wsl2 following microsoft's instructions
2. open a wsl terminal and run:

```bash
# update package list
sudo apt-get update

# install required tools
sudo apt-get install ffmpeg mp4v2-utils fd-find jq mediainfo python3 python3-pip

# create alias for fd
echo 'alias fd=fdfind' >> ~/.bashrc
source ~/.bashrc

# install python packages
pip3 install requests beautifulsoup4 fuzzywuzzy python-Levenshtein
```

## usage

### basic usage

process a single audiobook:

```bash
./audiobook_processor.sh /path/to/audiobook/folder
```

process a directory containing multiple audiobooks:

```bash
./audiobook_processor.sh /path/to/audiobooks
```

### specifying output directory

by default, processed audiobooks are saved to a `processed` subdirectory in the input folder. you can specify a different output directory:

```bash
./audiobook_processor.sh /path/to/audiobooks /path/to/output/directory
```

### non-interactive mode

for batch processing or automation, you can run in non-interactive mode:

```bash
AUDIOBOOKS_NON_INTERACTIVE=1 ./audiobook_processor.sh /path/to/audiobooks
```

in this mode, the script will use default values for any missing metadata rather than prompting for input.

## how it works

the script processes audiobooks in the following phases:

1. **discovery phase**: finds directories containing audio files
2. **metadata extraction**:
   - extracts info from directory and filenames
   - reads embedded id3/tag metadata
   - searches online sources for missing info
   - finds or downloads cover art
3. **processing phase**:
   - concatenates audio files
   - creates chapter markers
   - generates a single m4b file with proper metadata
4. **organization phase**:
   - determines proper category based on metadata
   - places file in organized directory structure

## directory structure

the script organizes audiobooks into the following structure:

```
output_dir/
├── Fiction/
│   ├── Fantasy/
│   │   └── Author Name/
│   │       └── Author Name - Book Title.m4b
│   ├── Science Fiction/
│   ├── Mystery & Thriller/
│   ├── Historical/
│   ├── Romance/
│   └── General/
├── Non-Fiction/
│   ├── History/
│   ├── Science/
│   ├── Self-Help/
│   ├── Biography/
│   ├── Business/
│   └── General/
├── Children/
├── Series/
│   └── Series Name/
│       └── Author Name - Series Name 1 - Book Title.m4b
└── Unsorted/
```

## handling file naming

the script can extract metadata from various filename formats:

- `Author - Title`
- `Author - Title (Year)`
- `Author - Series Name #X - Title`
- `Author - Series Name Book X - Title`
- `Title - Author - Narrator`
- `Title (Year) - Author`
- and more

## troubleshooting

### common issues

**issue**: script reports "command not found: fd"  
**solution**: on debian/ubuntu systems, fd is called fd-find. the installation script creates an alias, but you may need to restart your terminal or run `source ~/.bashrc`.

**issue**: no audio files found  
**solution**: ensure your audio files are in supported formats (mp3, m4a, flac, wav, aac) and the script has permission to access the directory.

**issue**: online metadata lookup fails  
**solution**: check your internet connection. the script will still work with local metadata if online lookup fails.

**issue**: the script processes the same audiobook more than once  
**solution**: this issue has been fixed in the latest version. The script now uses canonical paths to track processed directories and better detects already processed books.

**issue**: the script fails when processing multiple audiobooks  
**solution**: the latest version includes improved temp directory handling to prevent conflicts between processing runs.

**issue**: the script removes original files and things go wrong  
**solution**: use the `--keep-original-files` flag to preserve original files after processing. This is recommended for first-time users until you're confident the script works correctly.

## contributing

contributions are welcome! please feel free to submit a pull request.

## license

this project is licensed under the mit license - see the [license](LICENSE) file for details.

## acknowledgments

- ffmpeg for audio processing
- goodreads and librivox for metadata
- all the open source tools that make this project possible