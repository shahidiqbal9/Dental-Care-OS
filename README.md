Dental OS Care

Simple clinic manager for a receptionist and a dentist. No server, no install: open index.html.

Features
Login by role (PINs in app.js, default receptionist 1111, dentist 2222 - change them)
Patient: name, phone, address, age, gender, allergies/medical history
Full-mouth tooth chart (FDI 11-48): tap teeth, pick a procedure from the full list, fee auto-fills per tooth
Procedure status (planned / done), dentist adds, receptionist views
Payments, total, paid, remaining balance
Next follow-up date + reason, "Follow-ups due" filter
Upload mouth photos and X-rays (tag teeth), tap to enlarge
Backup / Restore JSON (includes images)
Run

Double-click index.html, or host free on GitHub Pages.

Push to GitHub
git init
git add .
git commit -m "Dental OS Care"
git branch -M main
git remote add origin https://github.com/YOURNAME/dental-os-care.git
git push -u origin main

GitHub Pages: repo Settings > Pages > Branch main / root.

Important

Data is stored in the browser of the computer in use (localStorage + IndexedDB). Receptionist and dentist must use the same PC/browser. Take Backups regularly. The PIN login is a simple screen lock, not real security. For multi-device use you need a backend (Firebase / Supabase), not included.
