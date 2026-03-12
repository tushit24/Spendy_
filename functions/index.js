const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * HTTP Callable Function: sendGroupNotification
 *
 * This function expects the following data payload from the Flutter client:
 * {
 *    "tokens": ["fcm_token_1", "fcm_token_2"],
 *    "title": "Notification Title",
 *    "body": "Notification Body content",
 *    "data": { "route": "/some_route" } // Optional
 * }
 */
exports.sendGroupNotification = functions.https.onCall(async (data, context) => {
    // 1. Verify Authentication (Optional but recommended)
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be logged in to send notifications."
        );
    }

    const { tokens, title, body, data: payloadData } = data;

    if (!tokens || !Array.isArray(tokens) || tokens.length === 0) {
        return { success: false, error: "No target tokens provided." };
    }

    // 2. Construct the FCM Multicast Message
    const message = {
        notification: {
            title: title || "New Notification",
            body: body || "",
        },
        data: payloadData || {},
        tokens: tokens, // Array of FCM tokens
    };

    try {
        // 3. Send the message via Admin SDK
        const response = await admin.messaging().sendEachForMulticast(message);

        console.log(`Successfully sent message to ${response.successCount} devices.`);
        if (response.failureCount > 0) {
            console.error(`Failed to send to ${response.failureCount} devices.`);
            // Optional: You can iterate over response.responses to remove dead tokens from Firestore here.
        }

        return { success: true, successCount: response.successCount };
    } catch (error) {
        console.error("Error sending FCM message:", error);
        throw new functions.https.HttpsError("internal", "Failed to send FCM message.", error);
    }
});
