# Security

Please don't report security problems in a public issue. Use GitHub's private reporting instead: on this repository, open the **Security** tab and choose **Report a vulnerability**. You'll get a reply there.

How Cool Head works, so you can judge what is a problem: it runs as your user, reads information about processes that macOS already lets your user read, and writes nothing to disk; what it needs while running stays in memory. It makes no network connections except when you press Look it up, which opens a web search for a process name in your browser. It can stop or slow a process only when you press a button that asks first, and only processes your user owns. It can offer to quit an app only if the app is installed in an Applications folder, and the app then quits normally, asking you to save.
