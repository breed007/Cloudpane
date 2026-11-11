---
title: Exporting and reports
order: 9
platforms: macOS, iOS
summary: CSV and JSON exports of a scan, and the PDF report.
---
# Exporting and reports

Every export is written under a new name and never replaces an existing file: if the name is taken, Cloudpane adds a number.

<!-- macOS -->
The exports are in Settings, and the files go to your Downloads folder.
<!-- /macOS -->

## CSV and JSON

Export CSV or Export JSON writes every file in the last scan with its provider, path, logical and allocated size, modification date, content type, whether it is a placeholder, and its hash when it has one. In the CSV, a name that starts with =, +, - or @ gets an apostrophe in front, so a spreadsheet cannot run it as a formula.

## The PDF report

Export PDF writes a summary of the latest complete scan: the overview, plans, the backup grade with each folder's explanation, files that exist in only one place, duplicate totals per tier, and history totals.

With Hide file paths and names in the report turned on, which it is at first, the report leaves out file paths, file names, folder names, account names (Google Drive's carries your email address) and backup location labels. Folders are numbered per provider instead, and single points of failure are counted per provider. The figures stay. Plan names you typed are included.

<!-- macOS -->
After an export, Reveal in Finder shows the file.
<!-- /macOS -->
