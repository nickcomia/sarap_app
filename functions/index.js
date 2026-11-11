const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Runs automatically whenever an account is deleted in Firebase Authentication.
exports.cleanupDeletedUser = functions
    .runWith({maxInstances: 5})
    .auth.user()
    .onDelete(async (user) => {
      const uid = user.uid;
      // Deletes users/{uid} and its subcollections (saved, mealPlan)
      await db.recursiveDelete(db.collection("users").doc(uid));
      await db.collection("profiles").doc(uid).delete();
    });