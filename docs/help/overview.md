---
title: Overview
order: 2
platforms: macOS, iOS
summary: The total in cloud storage, each provider's share, and the file types.
---
# Overview

Overview shows the totals from the latest scan.

## The headline

- Total in cloud storage: the logical size of every file in every provider folder. Backup locations are not counted.
- The part of it that is only in the cloud, meaning placeholders with no data on this Mac.
- Monthly cost: the total of your plans in [Providers](providers.md), leaving out bundles and inactive plans. Each currency is totaled on its own.
- When the last scan finished.

## By provider

Each provider gets a bar split into what is on this Mac and what is only in the cloud. When a plan size is set, the bar shows use against the plan; otherwise bars compare the providers with each other. A provider you added in Providers appears here too, and a plan with no folder reads "Plan only, not on this Mac".

The Edit plan or Add plan button on each row opens that provider's plan in Providers. Overview itself changes nothing.

<!-- macOS -->
Click a provider to see its top-level folders with their sizes. From there you can turn on hashing for a folder; see [Duplicates](duplicates.md).
<!-- /macOS -->

## Other cloud folders

Folders in `~/Library/CloudStorage` that match none of the five supported providers, such as a folder left by another sync app, are listed together as Other cloud folders. They are scanned like any provider, but they have no plan. To track one as its own provider with a plan, name it with Add provider in [Providers](providers.md#adding-a-provider).

## Banners

A banner appears above the totals when the numbers are incomplete:

- the last scan did not finish, so the totals cover only what it reached;
- a provider is a partial view or unavailable, with the reason (see [Troubleshooting](troubleshooting.md));
- providers that are not installed on this Mac;
- items that could not be read and are left out.

## By file type

Sizes and file counts grouped into documents, images, video, audio, archives, apps, code and other.
