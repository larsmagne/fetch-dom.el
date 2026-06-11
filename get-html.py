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

# Open Crome
chrome_options = webdriver.ChromeOptions()
prefs = {"profile.default_content_setting_values.notifications" : 2}
chrome_options.add_experimental_option("prefs", prefs)
chrome_options.add_argument("--disable-notifications")
# The default User-Agent is "HeadlessChrome", which imdb.com bans.
chrome_options.add_argument('--user-agent=' + user_agent)
if headless == "headless":
    chrome_options.add_argument("--headless=new")
chrome_options.add_argument("--disable-dev-shm-usage");
chrome_options.add_experimental_option('prefs', {'intl.accept_languages': 'en'})

# Give the chosen driver as an option to Chrome()
driver = webdriver.Chrome(options = chrome_options, service = service)

def save_cookies():
    pickle.dump(driver.get_cookies() , open(cookie_file, "wb"))

def load_cookies():
    if os.path.exists(cookie_file):
        cookies = pickle.load(open(cookie_file, "rb"))

        # Enables network tracking so we may use Network.setCookie method
        driver.execute_cdp_cmd('Network.enable', {})

        # Iterate through pickle dict and add all the cookies
        for cookie in cookies:
            # Fix issue Chrome exports 'expiry' key but expects
            # 'expire' on import
            if 'expiry' in cookie:
                cookie['expires'] = cookie['expiry']
                del cookie['expiry']

            # Set the actual cookie
            driver.execute_cdp_cmd('Network.setCookie', cookie)

        # Disable network tracking
        driver.execute_cdp_cmd('Network.disable', {})

# First load the top-level domain so that we can set the cookies.
# (This is apparently how Chrome/Selenium works.)
parsed = urlparse(url)
driver.get(f"{parsed.scheme}://{parsed.netloc}/")
load_cookies()

# Then get the actual URL we want the DOM for.
driver.get(url)

if float(wait) > 0:
    time.sleep(float(wait))

save_cookies()

print(driver.execute_script("return document.body.innerHTML;"))

driver.quit()
