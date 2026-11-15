# Security

Please don't report security problems in a public issue. Use GitHub's private reporting instead: on this repository, open the **Security** tab and choose **Report a vulnerability**. You'll get a reply there.

How Cool Head works, so you can judge what is a problem: it runs as your user, reads information about processes that macOS already lets your user read, and stores 24 hours of load history and 7 days of past cards in `~/Library/Application Support/Cool Head/`. It makes no network connections except when you press Look it up, which opens a web search for a process name in your browser. It can stop or slow a process only when you press a button that asks first, and only processes your user owns.
