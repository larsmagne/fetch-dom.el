This is an Emacs package to enable manual-intervention web scraping of
recalcitrant web sites.

`fetch-dom' is the main entry function in this package.  It will
try to fetch URL by using three methods:

* First try to fetch URL using the normal, fast method.

* If this fails, use Selenium headless.  This involves spinning up a
   web browser and then dumping the resulting DOM.

* If this fails, spin up Selenium and a web browser window.  This will
   allow the user to click around a bit, answering any challenges.

In 2) and 3), `fetch-dom' will save and reuse cookies, so that
hopefully 3) doesn't happen as much, and 1) and 2) will be
successful more often.

So this requires a Python/Selenium installation that works, and
Chromium installed.

Here's a recipe to install under Debian; your mileage may vary:

```
sudo apt install chromium chromium-driver python3-selenium
```

Then to use, say:

```
(push "~/src/fetch-dom.el/" load-path)
(require 'fetch-dom)
(fetch-dom "https://gnus.org/")
```

