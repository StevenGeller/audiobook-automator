# publishing to github

the audiobook-automator project is ready to be published to github. follow these steps to complete the process:

## creating the github repository

1. go to https://github.com/new
2. enter repository name: `audiobook-automator`
3. add a description: "a command-line tool for processing and organizing audiobooks"
4. choose visibility (public recommended)
5. do not initialize with readme, .gitignore, or license (we've already created these)
6. click "create repository"

## pushing the code

after creating the repository, run these commands to push the existing code:

```bash
# verify remote is set correctly (already done)
git remote -v

# push the code to github
git push -u origin main
```

if you haven't authenticated with github yet, you'll be prompted to do so.

## updating the repository

to make changes in the future:

```bash
# make your changes
# ...

# stage changes
git add .

# commit changes
git commit -m "description of your changes"

# push to github
git push
```

## creating a release

consider creating a release on github:

1. go to https://github.com/StevenGeller/audiobook-automator/releases/new
2. click "choose a tag" and create a new tag (e.g., "v1.0.0")
3. title: "audiobook-automator v1.0.0"
4. describe the release features
5. click "publish release"

this will make it easy for others to download specific versions of your software.