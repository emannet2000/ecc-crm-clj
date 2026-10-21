# Staff guides

The in-app **Help** link opens `web/public/guide.html` in a separate tab. It contains:

- **How to use**: Flor's daily workflow and handover checklist.
- **User manual**: student records, applications, requirements, milestones, photos, tasks, conversations, payments, access and the portal.
- **FAQ**: common problems and the limits of manual messaging.

Edit the HTML source when workflow labels change, then run `bash scripts/build-themed-web.sh`. The guide is copied into the frontend distribution and included in release integrity checks. Use the browser's Print command to save or print a staff copy. Keep account details, passwords and student information out of the public guide.
