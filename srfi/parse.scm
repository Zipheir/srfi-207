;;; Simple parser for string-notated bytevectors.

(define (parse)
  (let lp ((c (read-char)))
    (cond ((eof-object? c) (if #f #f))
          ((char=? c #\\)
           (let ((c* (read-char)))
             (cond ((eof-object? c*)
                    (raise (bytestring-error "incomplete escape sequence")))
                   ((escape c*) =>
                    (lambda (b)
                      (write-u8 b)
                      (lp (read-char))))
                   (else (lp (read-char))))))
          ((and (char>=? c #\space) (char<=? c #\~))
           (write-u8 (char->integer c))
           (lp (read-char)))
          (else (raise (bytestring-error "invalid character" c))))))

(define (escape c)
  (case c
    ((#\a) 7)
    ((#\b) 8)
    ((#\t) 9)
    ((#\n) 10)
    ((#\r) 13)
    ((#\x) (parse-hex))
    ((#\space #\tab)
     (skip-horizontal-whitespace)
     (skip-line-break)
     #f)                              ; skip
    ((#\newline)
     (skip-horizontal-whitespace)
     #f)                              ; skip
    (else (raise (bytestring-error "invalid escaped character" c)))))

(define (parse-hex)
  (let* ((hex1 (read-char))
         (hex2 (read-char)))
    (when (or (eof-object? hex1) (eof-object? hex2))
      (raise (bytestring-error "incomplete hexadecimal sequence")))
    (if (char=? hex2 #\;)
        (or (string->number (string hex1) 16)
            (raise (bytestring-error "invalid hexadecimal sequence")))
        (let ((term (read-char)))
          (if (eqv? term #\;)
              (or (string->number (string hex1 hex2) 16)
                  (raise (bytestring-error "invalid hexadecimal sequence")))
              (raise
               (bytestring-error
                "overlong or unterminated hexadecimal sequence")))))))

(define (skip-line-break)
  (let ((c (read-char)))
    (unless (eqv? #\newline c)
      (raise (bytestring-error "expected newline" c))))
  (skip-horizontal-whitespace))

(define (skip-horizontal-whitespace)
  (let lp ()
    (when (memv (peek-char) '(#\space #\tab))
      (read-char)
      (lp))))

(define (string->bytevector s)
  (parameterize ((current-input-port (open-input-string s))
                 (current-output-port (open-output-bytevector)))
    (parse)
    (get-output-bytevector (current-output-port))))
