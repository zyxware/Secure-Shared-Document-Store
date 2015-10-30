Secure Shared projects folder for distributed users
===================================================

We use a VPS server hosted on the web as our shared projects folder to share files between our team members in a safe and secure way. This is set up in such a way that users can mount a folder on the VPS on to their local machines via SSHFS and access contents on the shared folder. The permissions in the folder is managed via a script that is running on the server. The script and its configuration is being managed using an automatic deployment process using git. This is the script that we have created to manage the document store. You can read more about how to set this up on http://www.zyxware.com/articles/2456/setting-up-a-secure-shared-projects-folder-for-distributed-users .

