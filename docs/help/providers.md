---
title: Providers
order: 6
platforms: macOS, iOS
summary: Accounts, plans and their costs, and adding or removing providers.
---
# Providers

Providers lists every account Cloudpane knows about, with the plan you pay for each provider. Plan sizes and prices are not readable on the Mac, so you enter them once by hand.

## Accounts and plans

Each row shows the provider and account, its status, the space it used in the latest complete scan, the plan, the cost per month and the room left. Statuses are Installed, Partial view, Not installed, Unavailable, Not found (scanned before, missing now), Excluded from scans, and Not on this Mac (a plan with no folder).

There is one plan per provider. When a provider has several accounts, such as two OneDrive accounts, the plan shows once on the provider's row, and the used space, room left and months to full count every account.

## Entering a plan

Choose Add plan or Edit plan. Fill from catalog suggests plans from Cloudpane's built-in catalog of US prices; the footer gives the date of those prices. A price marked "Price not confirmed" should be checked on the provider's page. You can also type the name, price, currency, billing cycle, next payment, plan size and other details yourself. Plan sizes use decimal units, as providers sell them: 1 TB is 1,000,000,000,000 bytes.

Mark a plan as part of a bundle (Apple One, Google One family, Microsoft 365, employer-paid) to show it without adding it to the monthly cost. Inactive plans are left out too. Totals are kept per currency and never converted.

## What the numbers mean

- Per TB: the monthly price divided by the plan size.
- Room left: the plan size minus the space used. Over the plan shows as "Over by".
- Months to full: from growth between two complete scans at least a day apart.
- Under 5% used: a paid plan under 5% full in the latest complete scan and in one at least a day older, the same two scans growth uses.

Consolidation options show when one paid plan has room for everything in another plan in the same currency. They are options, shown next to the backup grade of the provider you would cancel, because canceling a provider removes a copy of your files. See [Backup grade](backup-grade.md).

## Adding a provider

Add provider offers three things:

- Supported service: how each of the five providers not on this Mac can appear, and Scan again. Cloudpane installs nothing and signs in to nothing.
- Plan without a folder: a provider you pay for that has no folder on this Mac. Its cost counts toward the monthly total; it has no space used, room left, months to full or backup grade, and no consolidation option moves files into it.
- Name a folder: gives a provider name to a folder in `~/Library/CloudStorage` that Cloudpane does not recognize. It becomes its own provider after the next scan. Its version history is unknown, so its grade never counts history as a pass.

A name that matches a supported provider or another provider you added is refused.

## The row menu

The ⋯ menu on each row offers what applies to it:

- Remove plan: forgets the price and size you entered, after you confirm.
- Exclude from scans: scans, the watcher and hashing skip the account. Cloudpane scans again without it, and older scans keep what they recorded. Include in scans brings it back.
- Forget: on an account marked Not found, hides the row until the account is found again.
- Remove from Cloudpane: on a provider you added, deletes it and its plan after you confirm. A named folder goes back to Other cloud folders at the next scan.

These change only Cloudpane's own records, never a provider's app or a file.

The [iCloud](icloud.md) section appears here when iCloud Drive is on this Mac, or once an iCloud plan, your iCloud total or a Photos library has been entered.
