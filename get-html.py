#!/usr/bin/python3
import time
import random
import json
import sys
import os
import pickle
from urllib.parse import urlparse
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import NoSuchElementException
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.service import Service as ChromeService

url = sys.argv[1]
headless = sys.argv[2]
user_agent = sys.argv[3]
wait = sys.argv[4]
cookie_file = sys.argv[5]

service = ChromeService(executable_path="/usr/bin/chromedriver")

# Open Chrome
chrome_options = webdriver.ChromeOptions()
prefs = {"profile.default_content_setting_values.notifications": 2}
chrome_options.add_experimental_option("prefs", prefs)
chrome_options.add_argument("--disable-notifications")
# The default User-Agent is "HeadlessChrome", which imdb.com bans.
chrome_options.add_argument('--user-agent=' + user_agent)
if headless == "headless":
    chrome_options.add_argument("--headless=new")
chrome_options.add_argument("--disable-dev-shm-usage")
chrome_options.add_experimental_option('prefs', {'intl.accept_languages': 'en'})

driver = webdriver.Chrome(options=chrome_options, service=service)


def save_cookies():
    pickle.dump(driver.get_cookies(), open(cookie_file, "wb"))


def load_cookies():
    if not os.path.exists(cookie_file):
        return

    cookies = pickle.load(open(cookie_file, "rb"))

    # Enable network tracking so we can use Network.setCookie
    driver.execute_cdp_cmd('Network.enable', {})

    for cookie in cookies:
        # Chrome exports 'expiry' but CDP's Network.setCookie expects 'expires'
        if 'expiry' in cookie:
            cookie['expires'] = cookie.pop('expiry')

        # CDP requires either 'url' or 'domain'+'path' to know where the
        # cookie applies. Selenium's get_cookies() gives us domain/path
        # already, so this is normally fine as-is. If 'domain' is missing
        # for some reason, fall back to deriving it from our target URL.
        if 'domain' not in cookie:
            parsed = urlparse(url)
            cookie['domain'] = parsed.netloc

        driver.execute_cdp_cmd('Network.setCookie', cookie)

    driver.execute_cdp_cmd('Network.disable', {})

load_cookies()
driver.get(url)

if float(wait) > 0:
    time.sleep(float(wait))

save_cookies()
print(driver.execute_script("return document.body.innerHTML;"))
driver.quit()
