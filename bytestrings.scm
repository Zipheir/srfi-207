;;; Copyright (C) 2020 Wolfgang Corcoran-Mathe
;;;
;;; Permission is hereby granted, free of charge, to any person obtaining a
;;; copy of this software and associated documentation files (the
;;; "Software"), to deal in the Software without restriction, including
;;; without limitation the rights to use, copy, modify, merge, publish,
;;; distribute, sublicense, and/or sell copies of the Software, and to
;;; permit persons to whom the Software is furnished to do so, subject to
;;; the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be included
;;; in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
;;; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;;; IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;;; CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;;; TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

;;;; Utility

(define (exact-natural? x)
  (and (integer? x) (exact? x) (not (negative? x))))

(define (ascii-char-or-integer? obj)
  (let ((int-obj (if (char? obj) (char->integer obj) obj)))
    (and (exact-natural? int-obj) (< int-obj 256))))

;;;; Error type

(define-record-type <bytestring-error>
  ;; TODO: More slots?
  (raw-bytestring-error message irritants)
  bytestring-error?
  (message bytestring-error-message)
  (irritants bytestring-error-irritants))

(define (bytestring-error message . irritants)
  (raw-bytestring-error message irritants))

;;;; Constructors

(define (list->bytestring lis)
  (assume (or (pair? lis) (null? lis)))
  (parameterize ((current-output-port (open-output-bytevector)))
    (for-each write-bytestring-segment lis)
    (get-output-bytevector (current-output-port))))

(define (write-bytestring-segment obj)
  ((cond ((and (exact-natural? obj) (< obj 256)) write-u8)
         ((and (char? obj) (char<? obj #\delete)) write-char)
         ((bytevector? obj) write-bytevector)
         ((string? obj) write-string)
         (else
          (raise (bytestring-error "invalid bytestring element" obj))))
   obj))

(define (bytestring . args)
  (list->bytestring args))

;;;; Conversion

(define (bytevector-u8-fold-right kons knil bvec)
  (let ((len (bytevector-length bvec)))
    (let rec ((i 0))
      (if (>= i len)
          knil
          (kons (bytevector-u8-ref bvec i)
                (rec (+ i 1)))))))

(define (integer->hex-string n)
  (let ((hex-raw (number->string n 16)))
    (if (even? (string-length hex-raw))
        hex-raw
        (string-append "0" hex-raw))))

(define (bytevector->hex-string bstring)
  (assume (bytevector? bstring))
  (let ((len (bytevector-length bstring)))
    (bytevector-u8-fold-right (lambda (byte hex)
                                (string-append (integer->hex-string byte) hex))
                              (string)
                              bstring)))

(define bytevector->base64
  (case-lambda
    ((bvec) (bytevector->base64 bvec "+/"))
    ((bvec digits)
     (assume (bytevector? bvec))
     (assume (string? digits))
     (base64-encode-bytevector bvec digits))))

(define base64->bytevector
  (case-lambda
    ((base64-string) (base64->bytevector base64-string "+/"))
    ((base64-string digits)
     (assume (string? base64-string))
     (assume (string? digits))
     ;; FIXME: ensure base64-string is ASCII(?)
     (base64-decode-bytevector (string->utf8 base64-string) digits))))

(cond-expand
  ((library (scheme bytevector))
   (define (bytestring->list bstring)
     (bytevector->u8-list bstring)))
  (else
   (define (bytestring->list bstring)
     (assume (bytevector? bstring))
     (list-tabulate (bytevector-length bstring)
                    (lambda (i) (bytevector-u8-ref bstring i))))))

;;;; Selection

(define (%bytestring-pad-left-or-right bstring len char-or-u8 right)
  (assume (bytevector? bstring))
  (assume (exact-natural? len))
  (unless (ascii-char-or-integer? char-or-u8)
    (error "invalid bytestring element" char-or-u8))
  (let ((pad-len (- len (bytevector-length bstring)))
        (pad-byte (if (char? char-or-u8)
                      (char->integer char-or-u8)
                      char-or-u8)))
    (if (<= pad-len 0)
        bstring
        (let ((padded (make-bytevector len pad-byte))
              (offset (if right 0 pad-len)))
          (bytevector-copy! padded offset bstring)
          padded))))

(define (bytestring-pad bstring len char-or-u8)
  (%bytestring-pad-left-or-right bstring len char-or-u8 #f))

(define (bytestring-pad-right bstring len char-or-u8)
  (%bytestring-pad-left-or-right bstring len char-or-u8 #t))

(define (bytestring-trim bstring pred)
  (assume (bytevector? bstring))
  (assume (procedure? pred))
  (let ((new-start (bytestring-index bstring
                                     (lambda (b) (not (pred b))))))
    (if new-start
        (bytevector-copy bstring new-start)
        (bytevector))))

(define (bytestring-trim-right bstring pred)
  (assume (bytevector? bstring))
  (assume (procedure? pred))
  (let ((new-end (+ 1 (bytestring-index-right bstring
                                              (lambda (b)
                                                (not (pred b)))))))
    (if new-end
        (bytevector-copy bstring 0 new-end)
        (bytevector))))

(define (bytestring-trim-both bstring pred)
  (assume (bytevector? bstring))
  (assume (procedure? pred))
  (let ((new-start (bytestring-index bstring
                                     (lambda (b) (not (pred b)))))
        (new-end (+ 1 (bytestring-index-right bstring
                                              (lambda (b)
                                                (not (pred b)))))))
    (bytevector-copy bstring
                     (or new-start 0)
                     (or new-end (bytevector-length bstring)))))

;;;; Replacement

(define bytestring-replace
  (case-lambda
    ((bstring1 bstring2 start end)
     (bytestring-replace bstring1 bstring2 start end start end))
    ((bstring1 bstring2 start1 end1 start2 end2)
     (assume (bytevector? bstring1))
     (assume (bytevector? bstring2))
     (assume (exact-natural? start1))
     (assume (exact-natural? end1))
     (assume (exact-natural? start2))
     (assume (exact-natural? end2))
     (let* ((b1-len (bytevector-length bstring1))
            (sub-len (- end2 start2))
            (new-len (+ sub-len (- b1-len (- end1 start1))))
            (bs-new (make-bytevector new-len)))
       (bytevector-copy! bs-new 0 bstring1 0 start1)
       (bytevector-copy! bs-new start1 bstring2 start2 end2)
       (bytevector-copy! bs-new (+ start1 sub-len) bstring1 end1 b1-len)
       bs-new))))

;;;; Comparison

(define (bytestring-prefix-length bstring1 bstring2)
  (let ((end (min (bytevector-length bstring1)
                  (bytevector-length bstring2))))
    (if (eqv? bstring1 bstring2)  ; fast path
        end
        (let lp ((i 0))
          (if (or (>= i end)
                  (not (= (bytevector-u8-ref bstring1 i)
                          (bytevector-u8-ref bstring2 i))))
              i
              (lp (+ i 1)))))))

;; A portable implementation can't rely on inlining, but it can
;; rely on macros.
;;
;; `byte' had better be an identifier!
(define-syntax u8-fold-case
  (syntax-rules ()
    ((_ byte)
     (if (and (<= 65 byte) (< byte 91))
         (+ 32 byte)
         byte))))

(define (u8-ci=? byte1 byte2)
  (= (u8-fold-case byte1) (u8-fold-case byte2)))

(define (u8-ci<? byte1 byte2)
  (< (u8-fold-case byte1) (u8-fold-case byte2)))

(define (bytestring-prefix-length-ci bstring1 bstring2)
  (let ((end (min (bytevector-length bstring1)
                  (bytevector-length bstring2))))
    (if (eqv? bstring1 bstring2)  ; fast path
        end
        (let lp ((i 0))
          (if (or (>= i end)
                  (not (u8-ci=? (bytevector-u8-ref bstring1 i)
                                (bytevector-u8-ref bstring2 i))))
              i
              (lp (+ i 1)))))))

;;; Primitive bytevector comparison functions.

(define (bytestring-compare bstring1 bstring2 res< res= res>)
  (let ((len1 (bytevector-length bstring1))
        (len2 (bytevector-length bstring2)))
    (let ((match (bytestring-prefix-length bstring1 bstring2)))
      (if (= match len1)
          (if (= match len2) res= res<)
          (if (= match len2)
              res>
              (if (< (bytevector-u8-ref bstring1 match)
                     (bytevector-u8-ref bstring2 match))
                  res<
                  res>))))))

(define (bytestring-compare-ci bstring1 bstring2 res< res= res>)
  (let ((len1 (bytevector-length bstring1))
        (len2 (bytevector-length bstring2)))
    (let ((match (bytestring-prefix-length-ci bstring1 bstring2)))
      (if (= match len1)
          (if (= match len2) res= res<)
          (if (= match len2)
              res>
              (if (u8-ci<? (bytevector-u8-ref bstring1 match)
                           (bytevector-u8-ref bstring2 match))
                  res<
                  res>))))))

(cond-expand
  ((library (scheme bytevector))
   (define (bytestring=? bstring1 bstring2)
     (bytevector=? bstring1 bstring2)))
  (else
   (define (bytestring=? bstring1 bstring2)
     (assume (bytevector? bstring1))
     (assume (bytevector? bstring2))
     (and (= (bytevector-length bstring1)
             (bytevector-length bstring2))
          (or (eqv? bstring1 bstring2)
              (bytestring-compare bstring1 bstring2 #f #t #f))))))

(define (bytestring<? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (not (eqv? bstring1 bstring2))
       (bytestring-compare bstring1 bstring2 #t #f #f)))

(define (bytestring>? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (not (eqv? bstring1 bstring2))
       (bytestring-compare bstring1 bstring2 #f #f #t)))

(define (bytestring<=? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (or (eqv? bstring1 bstring2)
      (bytestring-compare bstring1 bstring2 #t #t #f)))

(define (bytestring>=? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (or (eqv? bstring1 bstring2)
      (bytestring-compare bstring1 bstring2 #f #t #t)))

(define (bytestring-ci=? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (= (bytevector-length bstring1)
          (bytevector-length bstring2))
       (or (eqv? bstring1 bstring2)
           (bytestring-compare-ci bstring1 bstring2 #f #t #f))))

(define (bytestring-ci<? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (= (bytevector-length bstring1)
          (bytevector-length bstring2))
       (and (not (eqv? bstring1 bstring2))
            (bytestring-compare-ci bstring1 bstring2 #t #f #f))))

(define (bytestring-ci>? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (= (bytevector-length bstring1)
          (bytevector-length bstring2))
       (and (not (eqv? bstring1 bstring2))
            (bytestring-compare-ci bstring1 bstring2 #f #f #t))))

(define (bytestring-ci<=? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (= (bytevector-length bstring1)
          (bytevector-length bstring2))
       (or (eqv? bstring1 bstring2)
           (bytestring-compare-ci bstring1 bstring2 #t #t #f))))

(define (bytestring-ci>=? bstring1 bstring2)
  (assume (bytevector? bstring1))
  (assume (bytevector? bstring2))
  (and (= (bytevector-length bstring1)
          (bytevector-length bstring2))
       (or (eqv? bstring1 bstring2)
           (bytestring-compare-ci bstring1 bstring2 #f #t #t))))

;;;; Searching

(define bytestring-index
  (case-lambda
    ((bstring pred) (bytestring-index bstring pred 0))
    ((bstring pred start)
     (bytestring-index bstring pred start (bytevector-length bstring)))
    ((bstring pred start end)
     (assume (bytevector? bstring))
     (assume (procedure? pred))
     (assume (exact-natural? start))
     (assume (exact-natural? end))
     (let lp ((i start))
       (and (< i end)
            (if (pred (bytevector-u8-ref bstring i))
                i
                (lp (+ i 1))))))))

(define bytestring-index-right
  (case-lambda
    ((bstring pred) (bytestring-index-right bstring pred 0))
    ((bstring pred start)
     (bytestring-index-right bstring pred start (bytevector-length bstring)))
    ((bstring pred start end)
     (assume (bytevector? bstring))
     (assume (procedure? pred))
     (assume (exact-natural? start))
     (assume (exact-natural? end))
     (let lp ((i (- end 1)))
       (and (>= i start)
            (if (pred (bytevector-u8-ref bstring i))
                i
                (lp (- i 1))))))))

(define (bytestring-break bstring pred)
  (assume (bytevector? bstring))
  (assume (procedure? pred))
  (let ((end (bytevector-length bstring)))
    (let lp ((i 0))
      (if (> i end)
          (values bstring (bytevector))
          (if (pred (bytevector-u8-ref bstring i))
              (values (bytevector-copy bstring 0 i)
                      (bytevector-copy bstring i))
              (lp (+ i 1)))))))

(define (bytestring-span bstring pred)
  (assume (bytevector? bstring))
  (assume (procedure? pred))
  (let ((end (bytevector-length bstring)))
    (let lp ((i 0))
      (if (> i end)
          (values bstring (bytevector))
          (if (pred (bytevector-u8-ref bstring i))
              (lp (+ i 1))
              (values (bytevector-copy bstring 0 i)
                      (bytevector-copy bstring i)))))))

;;;; Joining & Splitting

(define (bytevector-concatenate bvecs)
  (fold-right bytevector-append
              (bytevector)
              bvecs))

;; Insert delimiter before each element of lis and append a tail
;; list at the end.
(define (%prepend-to-all+tail lis delimiter tail)
  (fold-right (lambda (elt rest)
                (cons delimiter (cons elt rest)))
              tail
              lis))

;; Insert delimiter before each element of lis.
(define (%prepend-to-all lis delimiter)
  (%prepend-to-all+tail lis '() delimiter))

;; Insert delimiter between every two elements of lis and after the
;; last element.
(define (%suffix-intersperse lis delimiter)
  (cons (car lis)
        (%prepend-to-all+tail (cdr lis) delimiter (list delimiter))))

;; Insert delimiter between every two elements of lis.
(define (%intersperse lis delimiter)
  (cons (car lis) (%prepend-to-all (cdr lis) delimiter)))

(define bytestring-join
  (case-lambda
    ((bstrings delimiter) (bytestring-join bstrings delimiter 'infix))
    ((bstrings delimiter grammar)
     (assume (or (pair? bstrings) (null? bstrings)))
     (assume (bytevector? delimiter))
     (if (pair? bstrings)
         (bytevector-concatenate
          (case grammar
            ((infix strict-infix) (%intersperse bstrings delimiter))
            ((prefix) (%prepend-to-all bstrings delimiter))
            ((suffix) (%suffix-intersperse bstrings delimiter))
            (else
             (raise (bytestring-error "invalid grammar" grammar)))))
         (if (eqv? grammar 'string-infix)
             (raise
              (bytestring-error "empty list with strict-infix grammar"))
             (bytevector))))))

(define (%find-right bstring byte end)
  (bytestring-index-right bstring (lambda (b) (= b byte)) 0 end))

(define (%skip-right bstring byte end)
  (bytestring-index-right bstring (lambda (b) (not (= b byte))) 0 end))

;; Infix split.  Thanks, Olin.
(define (%bytestring-split bstring delimiter)
  (let lp ((i (bytevector-length bstring)) (split '()))
    (cond ((and (>= i 0) (%skip-right bstring delimiter i)) =>
           (lambda (token-end-1)
             (let ((token-end (+ 1 token-end-1)))
               (cond ((%find-right bstring delimiter token-end-1) =>
                      (lambda (token-start-1)
                        (lp token-start-1
                            (cons (bytevector-copy bstring
                                                   (+ 1 token-start-1)
                                                   token-end)
                                  split))))
                     (else
                      (cons (bytevector-copy bstring 0 token-end)
                            split))))))
          (else split))))

(define (outliers bstring delimiter)
  (if (= (bytevector-length bstring) 0)
      (values '() '())
      (values
       (if (= delimiter (bytevector-u8-ref bstring 0))
                        (list (bytevector))
                        '())
       (if (= delimiter (bytevector-u8-ref
                         bstring
                         (- (bytevector-length bstring) 1)))
           (list (bytevector))
           '()))))

;; Tack-on empty prefix and suffix tokens.  Hacky.
(define (%bytestring-split/outliers bstring delimiter grammar)
  (let-values (((splits) (%bytestring-split bstring delimiter))
               ((prefix suffix) (outliers bstring delimiter)))
    (case grammar
      ((infix strict-infix) (append prefix splits suffix))
      ((prefix) (append splits suffix))
      ((suffix) (append prefix splits)))))

(define bytestring-split
  (case-lambda
    ((bstring delimiter) (bytestring-split bstring delimiter 'infix))
    ((bstring delimiter grammar)
     (assume (bytevector? bstring))
     (assume (ascii-char-or-integer? delimiter))
     (case grammar
       ((infix strict-infix)
        (%bytestring-split/outliers bstring delimiter))
       ((prefix)
        (%bytestring-split/outliers
         (bytestring-trim bstring (lambda (b) (= b delimiter)))
         delimiter))
       ((suffix)
        (%bytestring-split/outliers
         (bytestring-trim-right bstring (lambda (b) (= b delimiter)))
         delimiter))
       (else
        (raise (bytestring-error "invalid grammar" grammar)))))))

(define bytestring-split
  (case-lambda
    ((bstring delimiter) (bytestring-split bstring delimiter 'infix))
    ((bstring delimiter grammar)
     (assume (bytevector? bstring))
     (assume (ascii-char-or-integer? delimiter))
     (case grammar
       ((infix strict-infix)
        (%bytestring-split bstring delimiter))
       ((prefix)
        (%bytestring-split
         (bytestring-trim bstring (lambda (b) (= b delimiter)))
         delimiter))
       ((suffix)
        (%bytestring-split
         (bytestring-trim-right bstring (lambda (b) (= b delimiter)))
         delimiter))
       (else
        (raise (bytestring-error "invalid grammar" grammar)))))))

;;;; Output

(define (write-bytestring port . args)
  (assume (binary-port? port))
  (parameterize ((current-output-port port))
    (for-each
     (lambda (arg)
       (cond ((and (exact-natural? arg) (< arg 256)) (write-u8 arg))
             ((and (char? arg) (char<=? arg #\delete))
              (write-u8 (char->integer arg)))
             ((bytevector? arg) (write-bytevector arg))
             ;; TODO: Ensure ASCII.
             ((string? arg) (write-bytevector (string->utf8 arg)))
             (else (raise (bytestring-error "invalid bytestring element"
                                            arg)))))
     args)))
