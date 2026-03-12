# SPENDY: Complete Notification System Setup Guide

This guide walks you through the backend and final Firebase configurations to make Push Notifications functional, specifically securely leveraging Firebase Cloud Functions to avoid hard-coding FCM server keys in the frontend app.

## Prerequisites
- SPENDY Flutter app with Firebase Auth and Firestore already configured (`firebase_options.dart` generated).
- A Firebase project upgraded to the "Blaze" (Pay-as-you-go) plan. (Required for Cloud Functions. Note: it still has a generous free tier for college projects).
- Node.js installed on your development machine.

---

## 1. Firebase Service Account Setup (Client-Side Sending)

Since you are using the free **Spark Plan** and cannot deploy Firebase Cloud Functions, we have refactored the app to securely request and send FCM HTTP V1 Push Notifications **directly from the Flutter Client**.

**Warning:** Embedding a Service Account JSON in client-side code is acceptable for a college project demo, but it **is not recommended for production applications** due to the risk of reverse-engineering.

### Step-by-Step Instructions to enable pushes:
1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your project **"spendy"**.
3. In the top-left, click the gear icon next to "Project Overview" and select **"Project settings"**.
4. Navigate to the **"Service accounts"** tab.
5. Ensure the "Node.js" option is selected and click the **"Generate new private key"** button at the bottom.
6. A `.json` file will download to your computer.
7. Open this `.json` file. It will look something like this:
   ```json
   {
     "type": "service_account",
     "project_id": "spendy-e601d",
     "private_key_id": "...",
     "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
     "client_email": "...",
     "client_id": "...",
     "auth_uri": "...",
     "token_uri": "...",
     "auth_provider_x509_cert_url": "...",
     "client_x509_cert_url": "..."
   }
   ```
8. **Copy the ENTIRE contents** of that JSON file.
9. Open `lib/services/notification_service.dart` in your Flutter project.
10. Scroll down to the bottom of the file to the `_getAccessToken()` method.
11. Paste your exact JSON payload inside the `serviceAccountJson` variable:
   ```dart
   final serviceAccountJson = {
       "type": "service_account",
       "project_id": "spendy-e601d",
       // ... PASTE THE ENTIRE JSON HERE ...
   };
   ```
12. Save the file and reload your app. **The Notification System is now 100% active!**


## 2. Testing the Implementation

### A. Local Reminders
1. Build and run the app on an Android Emulator (`flutter run`).
2. Go to **Profile -> Settings** (Gear icon).
3. Ensure "Daily Morning Reminder" is toggled ON.
4. Click **Test Notification**.
   **Verify:** An immediate local push notification should appear at the top of the emulator screen.

### B. Group Actions (Remote FCM)
1. Ensure the Cloud Function is deployed and the URL is configured in `notification_service.dart`.
2. Install the app on **Emulator A** (logged in as User A).
3. Install the app on **Emulator B** (logged in as User B).
4. Run the app on both.
5. On Emulator A, **Create a Group**. Share the code with Emulator B.
6. On Emulator B, **Join the Group**.
   **Verify:** Emulator A should receive a push notification: *"User B joined..."*
7. On Emulator A, **Add an Expense** to the group.
   **Verify:** Emulator B should receive a push notification: *"User A added an expense..."*

---

## 3. Important Notes for College Project Presentation
- **Permissions:** Android 13+ requires users to explicitly grant push notification permissions. The app handles this on initial login.
- **Battery Optimization:** Real physical devices may suppress background notifications if the app is heavily battery-optimized.
- **Security:** By routing the push through Cloud Functions with `firebase-admin`, you successfully demonstrated secure frontend separation. Server keys are never exposed in the APK.
