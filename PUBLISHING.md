# Publishing To GitHub

This repository is prepared for GitHub publication.

Recommended repository name:

```text
TheParasites_QuickStack
```

## Important License Note

This mod is not open source.

When creating the GitHub repository, do not select an open-source license
template. The custom terms are already included in:

```text
LICENSE.md
COPYRIGHT_AND_TERMS.txt
```

Third-party components remain under their own licenses. See:

```text
THIRD_PARTY_NOTICES.md
licenses\UE4SS-MIT-LICENSE.txt
```

## Create The Repository

1. Create a new GitHub repository.
2. Use the repository name `TheParasites_QuickStack`, or another name you
   prefer.
3. Choose public or private.
4. Do not initialize it with a README, license, or gitignore.

## Push The Local Repository

Run these commands from this local repository folder:

```powershell
cd "<local repository folder>"
git remote add origin https://github.com/YOUR_GITHUB_NAME/TheParasites_QuickStack.git
git push -u origin main
git push origin v1.0.0
```

If you use SSH instead of HTTPS:

```powershell
cd "<local repository folder>"
git remote add origin git@github.com:YOUR_GITHUB_NAME/TheParasites_QuickStack.git
git push -u origin main
git push origin v1.0.0
```

## Create The GitHub Release

1. Open the GitHub repository.
2. Go to Releases.
3. Draft a new release.
4. Select the existing tag:

```text
v1.0.0
```

5. Release title:

```text
The Parasites QuickStack v1.0.0
```

6. Paste the contents of:

```text
RELEASE_NOTES_v1.0.0.md
```

7. Attach the release ZIP:

```text
<release ZIP path>\TheParasites_QuickStack_v1.0.0.zip
```

8. Publish the release.
