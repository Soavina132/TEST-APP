import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";

// Firebase web config (public — safe for frontend)
const firebaseConfig = {
  apiKey: "AIzaSyCZZ5bMm9dNztczZkqMIJWY6kOSpoRZq-g",
  authDomain: "lalao-mada-dd341.firebaseapp.com",
  projectId: "lalao-mada-dd341",
  storageBucket: "lalao-mada-dd341.firebasestorage.app",
  messagingSenderId: "334203069709",
  appId: "1:334203069709:web:e5058f37f8bbeb0cf8bc44",
};

let _app: ReturnType<typeof initializeApp> | null = null;
let _auth: ReturnType<typeof getAuth> | null = null;

function getFirebase() {
  if (!_app) {
    _app = initializeApp(firebaseConfig);
    _auth = getAuth(_app);
  }
  return { app: _app, auth: _auth! };
}

export { getFirebase };
