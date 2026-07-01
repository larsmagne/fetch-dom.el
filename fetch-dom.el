;;; fetch-dom.el --- Fetch HTML -*- lexical-binding: t -*-

;; Copyright (C) 2026 Lars Ingebrigtsen.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>

;; fetch-dom is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; fetch-dom is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;;; Commentary:

;; `fetch-dom' is the main entry function in this package.  It will
;; try to fetch URL by using three methods:

;; 1) First try to fetch URL using the normal, fast method.

;; 2) If this fails, use Selenium headless.  This involves spinning up
;;    a web browser and then dumping the resulting DOM.

;; 3) If this fails, spin up Selenium and a web browser window.  This
;;    will allow the user to click around a bit, answering any
;;    challenges.

;; In 2) and 3), `fetch-dom' will save and reuse cookies, so that
;; hopefully 3) doesn't happen as much, and 1) and 2) will be
;; successful more often.

;;; Code:

(require 'cl-lib)

(defvar fetch-dom-user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
  "User-Agent used when fetching data.")

(defvar fetch-dom-wait-period-headless 0
  "Number of seconds to wait before returning result when headless.")

(defvar fetch-dom-wait-period-popup 10
  "Number of seconds to wait before returning result when popping up window.")

(defvar fetch-dom-cookie-file "~/.emacs.d/fetch-dom.pickle"
  "The Pickle file used to save cookies.")

(defvar fetch-dom--host-values (make-hash-table :test #'equal))
(defvar fetch-dom--values-time nil)

(cl-defstruct fetch-dom
  url wait-period-headless wait-period-popup
  user-agent type callback min-level max-level)

(cl-defun fetch-dom (url &key wait-period-headless wait-period-popup
			 user-agent (type 'dom)
			 callback (min-level 'internal)
			 (max-level 'popup))
  "Fetch URL.

By default, the DOM is returned, but this is controlled by the
`:type' keyword.  Values are `dom' (the default),
`string' (return the results as a string) and `buffer' (return a
buffer containing the data).

`:min-level' is the level to start at.  Valid values are `internal',
`headless' and `popup'.

`:max-level' is the maximum level to end and.  Valid values are
the same as `:min-level'.

If `:callback' is given, the function will be asynchronous and
the callback argument will be called (with a single parameter --
the result)."
  (when (or (not fetch-dom--values-time)
	    (> (- (float-time) fetch-dom--values-time) 600))
    (setq fetch-dom--values-time nil
	  fetch-dom--host-values (make-hash-table :test #'equal)))
  (let ((done nil))
    (setq fetch-dom--values-time (float-time))
    (fetch-dom--async-1
     (make-fetch-dom
      :url url
      :callback (or callback
		    (lambda (result)
		      (setq done (list result))))
      :wait-period-headless wait-period-headless
      :wait-period-popup wait-period-popup
      :user-agent user-agent
      :type type
      :min-level min-level
      :max-level max-level))
    (unless callback
      (while (not done)
	(sit-for 0.01))
      (car done))))

(defun fetch-dom--async-1 (call)
  (let ((host (url-host (url-generic-parse-url (fetch-dom-url call)))))
    ;; First try to fetch using url.el.
    (if (or (not (fetch-dom--try-internal-p host))
	    (not (eq (fetch-dom-min-level call) 'internal)))
	(fetch-dom--async-2 call)
      (fetch-dom--internal
       (fetch-dom-url call)
       (or (fetch-dom-user-agent call) fetch-dom-user-agent)
       (lambda (_)
	 ;; Remove HTTP headers.
	 (goto-char (point-min))
	 (if (not (search-forward "\n\n" nil t))
	     (delete-region (point-min) (point-max))
	   (delete-region (point-min) (point)))
	 (if (not (fetch-dom--got-result-p))
	     (progn
	       (fetch-dom--failure 'internal host)
	       (if (eq (fetch-dom-max-level call) 'internal)
		   (fetch-dom--callback call)
		 (fetch-dom--async-2 call)))
	   (fetch-dom--success 'internal host)
	   (fetch-dom--callback call)))))))

(defun fetch-dom--async-2 (call)
  (let ((host (url-host (url-generic-parse-url (fetch-dom-url call)))))
    (if (or (not (fetch-dom--try-headless-p host))
	    (not (eq (fetch-dom-min-level call) 'headless)))
	(fetch-dom--async-3 call)
      (fetch-dom--selenium
       (fetch-dom-url call) "headless"
       (or (fetch-dom-wait-period-headless call)
	   fetch-dom-wait-period-headless)
       (or (fetch-dom-user-agent call) fetch-dom-user-agent)
       (lambda ()
	 (if (not (fetch-dom--got-result-p))
	     (progn
	       (fetch-dom--failure 'headless host)
	       (if (eq (fetch-dom-max-level call) 'headless)
		   (fetch-dom--callback call)
		 (fetch-dom--async-3 call)))
	   (fetch-dom--success 'headless host)
	   (fetch-dom--callback call)))))))

(defun fetch-dom--callback (call)
  (funcall (fetch-dom-callback call)
	   (fetch-dom--return-result (fetch-dom-type call))))

(defun fetch-dom--async-3 (call)
  (let ((host (url-host (url-generic-parse-url (fetch-dom-url call)))))
    (fetch-dom--selenium
     (fetch-dom-url call) "popup"
     (or (fetch-dom-wait-period-popup call)
	 fetch-dom-wait-period-popup)
     (or (fetch-dom-user-agent call) fetch-dom-user-agent)
     (lambda ()
       (if (not (fetch-dom--got-result-p))
	   (fetch-dom--failure 'popup host)
	 (fetch-dom--success 'popup host))
       (fetch-dom--callback call)))))

(defun fetch-dom--success (type host)
  (push type (gethash host fetch-dom--host-values)))

(defun fetch-dom--failure (type host)
  (let ((symbol (intern (format "fail-%s" type)))
	(values (gethash host fetch-dom--host-values)))
    (unless (eq (cadr values) symbol)
      (push symbol (gethash host fetch-dom--host-values)))
    nil))

(defun fetch-dom--try-internal-p (host)
  (let ((values (gethash host fetch-dom--host-values)))
    ;; If we've never tried before, then let's try.
    (or (null values)
	;; Or if we've got a previously successful one newer than a
	;; failure.
	(fetch-dom--newer-p 'internal 'fail-internal values)
	;; Or we've been through a successful higher-level more
	;; recently and there's no failures.
	(and (eq (car values) 'headless)
	     (not (eq (cadr values) 'headless)))
	(and (eq (car values) 'popup)
	     (not (eq (cadr values) 'popup))))))

(defun fetch-dom--try-headless-p (host)
  (let ((values (gethash host fetch-dom--host-values)))
    ;; If we've never tried before, then let's try.
    (or (null values)
	(not (eq (car values) 'popup))
	;; Or if we've got a previously successful one.
	(fetch-dom--newer-p 'headless 'fail-headless values)
	;; Or we've been through a successful popup once.
	(and (eq (car values) 'popup)
	     (not (eq (cadr values) 'popup))))))

(defun fetch-dom--newer-p (type1 type2 values)
  (let ((p1 (seq-position values type1))
	(p2 (seq-position values type2)))
    (and p1
	 (or (null p2)
	     (< p1 p2)))))

(defun fetch-dom--got-result-p ()
  ;; We say that the fetch failed if there's very little data, or
  ;; whether there's very few HTML nodes.  This may need adjusting.
  (let ((result
	 (and (> (buffer-size) 100)
	      (> (fetch-dom--count (libxml-parse-html-region
				    (point-min) (point-max)))
		 10))))
    (unless result
      (kill-buffer (current-buffer)))
    result))

(defun fetch-dom--count (dom)
  (let ((count 0)
	func)
    (setq func 
	  (lambda (dom)
	    (cl-incf count)
	    (mapcar func (dom-non-text-children dom))))
    (funcall func dom)
    count))

(defun fetch-dom--return-result (type)
  (pcase type
    (`dom (prog1
	      (libxml-parse-html-region (point-min) (point-max))
	    (kill-buffer (current-buffer))))
    (`string (prog1
		 (buffer-string)
	       (kill-buffer (current-buffer))))
    (`buffer (current-buffer))))

(defun fetch-dom--internal (url user-agent callback)
  (let ((cookies
	 (and
	  (file-exists-p fetch-dom-cookie-file)
	  (with-temp-buffer
	    (let ((default-directory (file-name-directory
				      (locate-library "fetch-dom"))))
	      (call-process (expand-file-name "print-cookies.py") nil t nil
			    (expand-file-name fetch-dom-cookie-file))
	      (goto-char (point-min))
	      (json-parse-buffer :object-type 'plist)))))
	;; Don't overwrite the user's real cookies.
	(url-cookie-secure-storage nil)
	(url-cookie-storage nil)
	(url-user-agent user-agent))
    (cl-loop for cookie across cookies
	     do (url-cookie-store
		 (plist-get cookie 'name)
		 (plist-get cookie 'value)
		 (plist-get cookie 'expiry)
		 (plist-get cookie 'domain)
		 (plist-get cookie 'path)
		 (plist-get cookie 'secure)))
    (url-retrieve url callback nil t)))

(defun fetch-dom--selenium (url headless wait-period user-agent callback)
  (with-current-buffer (generate-new-buffer "*fetch-dom*")
    (let ((default-directory (file-name-directory
			      (locate-library "fetch-dom"))))
      (make-process
       :name "get-html"
       :buffer (current-buffer)
       :command (list (expand-file-name "get-html.py")
		      url
		      headless
		      user-agent
		      (format "%d" wait-period)
		      (expand-file-name fetch-dom-cookie-file))
       :sentinel
       (lambda (proc _status)
	 (unless (process-live-p proc)
	   (with-current-buffer (process-buffer proc)
	     (funcall callback))))))))

(provide 'fetch-dom)

;;; fetch-dom.el ends here
