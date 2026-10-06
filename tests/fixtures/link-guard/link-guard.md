# Links to files the system would run

A clicked link to a local file opens directly only when the file, with
symlinks resolved, is something macOS just displays: an image, audio or video,
a PDF, plain text that is not a script or a playlist, or a plain folder, and
only when the file has not chosen an app of its own (a per-file "Open With",
which git does not keep, so that case is covered by tests only). Anything else is
shown in Finder after an explanation, because `NSWorkspace.open` means "run"
for an app, an installer, a script, and for several file types that hand the
click to something that runs. `LinkTargetPolicy` decides; its tests build every
case below as a real file (`LinkTargetPolicyTests`).

The files in this folder are harmless stand-ins. `looks-like-notes.txt` is a
symlink to Calculator, and the `.terminal` and `.fileloc` files are empty. The
danger they stand for is a cloned repository or an unzipped archive that ships
a symlink to its own app, or a `.terminal` file carrying a startup command, next
to a README. Git does not quarantine what it checks out, so Gatekeeper may never
ask.

Open this file in the **app window**. Quick Look opens only web and mail links,
so none of these do anything there, and that is a pass too.

## Shown in Finder, never opened

> **EXPECT:** each link brings up a sheet: "“…” is shown in Finder, not
> opened." **Show in Finder** selects the file in Finder; **Cancel** does
> nothing. For the first link the sheet names **Calculator.app**, the real
> target, not the symlink.
>
> **FAIL IF:** Calculator starts, Terminal opens, or any app opens the file.

- [A symlink named like a text file](looks-like-notes.txt)
- [An empty Terminal settings file](empty.terminal)
- [An empty file location](empty.fileloc)

## Opened directly

> **EXPECT:** each opens straight away, with no sheet: the image in Preview (or
> your image viewer), the text file in your text editor, the folder in Finder.
>
> **FAIL IF:** a sheet appears for any of these.

- [An image](../shared-images/logo.png)
- [A plain text file](plain.txt)
- [A folder](../shared-images)
