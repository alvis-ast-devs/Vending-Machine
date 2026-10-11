# 🛒 Smart IoT Vending Machine System

An end-to-end, smart vending machine ecosystem that integrates embedded hardware, a mobile client, a robust Python backend, a web-based admin dashboard, and modern QRIS cashless payment processing.

---

## 🚀 Tech Stack

### Hardware & Embedded
* **Microcontroller:** ESP32 (Arduino `.ino`)
* **Communication:** Serial / Wi-Fi / Local MQTT / HTTP

### Software & Applications
* **Mobile Client:** Flutter (User interaction & purchasing flow)
* **Backend Core:** Python 
* **Admin Web Dashboard:** React, Tailwind CSS (Hosted locally via PC hotspot)
* **Payment Gateway:** QRIS Cashless Integration

---

## 🛠️ System Architecture

1. **Hardware Layer (ESP32):** Controls physical dispensing mechanisms, sensors, and communicates status updates to the local network.
2. **Mobile App (Flutter):** Provides a seamless interface for users to browse products, view details, and initiate purchases.
3. **Payment System:** Generates and validates **QRIS** transactions for instant cashless payments.
4. **Backend & Admin Panel (Python & React):** Manages inventory, monitors machine status, logs transaction history, and allows administrators to oversee operations via a local web dashboard connected through the PC's hotspot.

---

## 📂 Project Structure

```text
├── hardware/         # ESP32 firmware (.ino files and wiring configurations)
├── backend/          # Python backend server and API endpoints
├── frontend-admin/   # React & Tailwind CSS web dashboard for administrators
└── mobile-app/       # Flutter mobile application client
