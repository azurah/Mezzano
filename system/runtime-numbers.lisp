(in-package :sys.int)

(declaim (inline integerp))
(defun integerp (object)
  (or (system:fixnump object)
      (bignump object)))

(defun rationalp (object)
  (or (integerp object)
      (ratiop object)))

(defun realp (object)
  (or (rationalp object)
      (floatp object)))

(defun numberp (object)
  (or (realp object)
      (complexp object)))

(defstruct (ratio
             (:constructor make-ratio (numerator denominator))
             (:predicate ratiop))
  numerator
  denominator)

(defun numerator (rational)
  (etypecase rational
    (ratio (ratio-numerator rational))
    (integer rational)))

(defun denominator (rational)
  (etypecase rational
    (ratio (ratio-denominator rational))
    (integer 1)))

(defstruct (complex
             (:constructor make-complex (realpart imagpart))
             (:predicate complexp))
  realpart
  imagpart)

(defun complex (realpart &optional imagpart)
  (check-type realpart real)
  (check-type imagpart (or real null))
  (unless imagpart (setf imagpart (coerce 0 (type-of realpart))))
  (if (and (integerp realpart) (zerop imagpart))
      realpart
      (make-complex realpart imagpart)))

(defun realpart (number)
  (if (complexp number)
      (complex-realpart number)
      number))

(defun imagpart (number)
  (if (complexp number)
      (complex-imagpart number)
      0))

(defun expt (base power)
  (check-type power (integer 0))
  (let ((accum 1))
    (dotimes (i power accum)
      (setf accum (* accum base)))))

(defstruct (byte (:constructor byte (size position)))
  (size 0 :type (integer 0) :read-only t)
  (position 0 :type (integer 0) :read-only t))

(declaim (inline %ldb ldb %dbp dpb %ldb-test ldb-test logbitp))
(defun %ldb (size position integer)
  (logand (ash integer (- position))
          (1- (ash 1 size))))

(defun ldb (bytespec integer)
  (%ldb (byte-size bytespec) (byte-position bytespec) integer))

(defun %dpb (newbyte size position integer)
  (let ((mask (1- (ash 1 size))))
    (logior (ash (logand newbyte mask) position)
            (logand integer (lognot (ash mask position))))))

(defun dpb (newbyte bytespec integer)
  (%dpb newbyte (byte-size bytespec) (byte-position bytespec) integer))

(defun %ldb-test (size position integer)
  (not (eql 0 (%ldb size position integer))))

(defun ldb-test (bytespec integer)
  (%ldb-test (byte-size bytespec) (byte-position bytespec) integer))

(defun logbitp (index integer)
  (ldb-test (byte 1 index) integer))

;;; From SBCL 1.0.55
(defun ceiling (number &optional (divisor 1))
  ;; If the numbers do not divide exactly and the result of
  ;; (/ NUMBER DIVISOR) would be positive then increment the quotient
  ;; and decrement the remainder by the divisor.
  (multiple-value-bind (tru rem) (truncate number divisor)
    (if (and (not (zerop rem))
             (if (minusp divisor)
                 (minusp number)
                 (plusp number)))
        (values (+ tru 1) (- rem divisor))
        (values tru rem))))

(define-lap-function %%coerce-fixnum-to-float ()
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:sar64 :rax 3)
  (sys.lap-x86:cvtsi2ss64 :xmm0 :rax)
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun float (number &optional prototype)
  (declare (ignore prototype))
  (etypecase number
    (float number)
    (fixnum (%%coerce-fixnum-to-float number))
    (ratio (/ (float (numerator number) prototype)
              (float (denominator number) prototype)))))

(define-lap-function %single-float-as-integer ()
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:mov64 :r8 :rax)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(define-lap-function %integer-as-single-float ()
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 3)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun float-nan-p (float)
  (let* ((bits (%single-float-as-integer float))
         (exp (ldb (byte 8 23) bits))
         (sig (ldb (byte 23 0) bits)))
    (and (eql exp #xFF)
         (not (zerop sig)))))

(defun float-trapping-nan-p (float)
  (let* ((bits (%single-float-as-integer float))
         (exp (ldb (byte 8 23) bits))
         (sig (ldb (byte 23 0) bits)))
    (and (eql exp #xFF)
         (not (zerop sig))
         (not (ldb-test (byte 1 22) sig)))))

(defun float-infinity-p (float)
  (let* ((bits (%single-float-as-integer float))
         (exp (ldb (byte 8 23) bits))
         (sig (ldb (byte 23 0) bits)))
    (and (eql exp #xFF)
         (zerop sig))))

(define-lap-function %%bignum-< ()
  (sys.lap-x86:push 0) ; align
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:xor64 :r10 :r10) ; CF save register.
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last-compare)
  (sys.lap-x86:clc) ; Avoid setting low bits in r10.
  (sys.lap-x86:rcl64 :r10 1) ; Restore saved carry.
  (sys.lap-x86:sbb64 :rsi :rdi)
  (sys.lap-x86:rcr64 :r10 1) ; Save carry.
  (sys.lap-x86:jmp loop)
  last-compare
  (sys.lap-x86:clc) ; Avoid setting low bits in r10.
  (sys.lap-x86:rcl64 :r10 1) ; Restore saved carry.
  (sys.lap-x86:sbb64 :rsi :rdi)
  (sys.lap-x86:mov64 :r8 nil)
  (sys.lap-x86:mov64 :r9 t)
  (sys.lap-x86:cmov64l :r8 :r9)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:add64 :csp 8)
  (sys.lap-x86:ret)
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume))

(define-lap-function %%float-< ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Compare.
  (sys.lap-x86:ucomiss :xmm0 :xmm1)
  (sys.lap-x86:mov64 :r8 nil)
  (sys.lap-x86:mov64 :r9 t)
  (sys.lap-x86:cmov64b :r8 :r9)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-< (x y)
  (check-type x real)
  (check-type y real)
  (cond
    ((and (fixnump x)
          (fixnump y))
     ;; Should be handled by binary-<.
     (error "FIXNUM/FIXNUM case hit GENERIC-<"))
    ((and (fixnump x)
          (bignump y))
     (%%bignum-< (%make-bignum-from-fixnum x) y))
    ((and (bignump x)
          (fixnump y))
     (%%bignum-< x (%make-bignum-from-fixnum y)))
    ((and (bignump x)
          (bignump y))
     (%%bignum-< x y))
    ((or (floatp x)
         (floatp y))
     ;; Convert both arguments to the same kind of float.
     (let ((x* (if (floatp y)
                   (float x y)
                   x))
           (y* (if (floatp x)
                   (float y x)
                   y)))
       (%%float-< x* y*)))
    ((or (ratiop x)
         (ratiop y))
       (< (* (numerator x) (denominator y))
          (* (numerator y) (denominator x))))
    (t (error "TODO... Argument combination ~S and ~S not supported." x y))))

;; Implement these in terms of <.
(defun generic->= (x y)
  (not (generic-< x y)))

(defun generic-> (x y)
  (generic-< y x))

(defun generic-<= (x y)
  (not (generic-< y x)))

(define-lap-function %%bignum-= ()
  (sys.lap-x86:push 0) ; align
  ;; Read headers.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:cmp64 :rax (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:jne different)
  ;; Same length, compare words.
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:xor32 :ecx :ecx)
  loop
  (sys.lap-x86:mov64 :rdx (:r8 #.(+ (- +tag-array-like+) 8) (:rcx 8)))
  (sys.lap-x86:cmp64 :rdx (:r9 #.(+ (- +tag-array-like+) 8) (:rcx 8)))
  (sys.lap-x86:jne different)
  test
  (sys.lap-x86:add64 :rcx 1)
  (sys.lap-x86:cmp64 :rcx :rax)
  (sys.lap-x86:jb loop)
  (sys.lap-x86:mov64 :r8 t)
  done
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret)
  different
  (sys.lap-x86:mov64 :r8 nil)
  (sys.lap-x86:jmp done))

(define-lap-function %%float-= ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Compare.
  (sys.lap-x86:ucomiss :xmm0 :xmm1)
  (sys.lap-x86:mov64 :r8 t)
  (sys.lap-x86:mov64 :r9 nil)
  ;; If the P bit is set then the values are unorderable.
  (sys.lap-x86:cmov64p :r8 :r9)
  (sys.lap-x86:cmov64ne :r8 :r9)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-= (x y)
  (check-type x number)
  (check-type y number)
  ;; Must not use EQ when the arguments are floats.
  (cond
    ((or (complexp x)
         (complexp y))
     (and (= (realpart x) (realpart y))
          (= (imagpart x) (imagpart y))))
    ((or (floatp x)
         (floatp y))
     ;; Convert both arguments to the same kind of float.
     (let ((x* (if (floatp y)
                   (float x y)
                   x))
           (y* (if (floatp x)
                   (float y x)
                   y)))
       (%%float-= x* y*)))
    ((or (fixnump x)
         (fixnump y))
     (eq x y))
    ((and (bignump x)
          (bignump y))
     (or (eq x y) (%%bignum-= x y)))
    ((or (ratiop x)
         (ratiop y))
     (and (= (numerator x) (numerator y))
          (= (denominator x) (denominator y))))
    (t (error "TODO... Argument combination ~S and ~S not supported." x y))))

(define-lap-function %%bignum-truncate ()
  ;; Read headers.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; TODO: Full division...
  (sys.lap-x86:cmp64 :rdx 1)
  (sys.lap-x86:jne not-implemented)
  (sys.lap-x86:cmp64 :rax 2)
  (sys.lap-x86:je 128-bit-number)
  (sys.lap-x86:cmp64 :rax 1)
  (sys.lap-x86:jne not-implemented)
  ;; 64-bit divide.
  (sys.lap-x86:mov64 :rax (:r8 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:mov64 :rcx (:r9 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:cqo)
  ;; Quotient in RAX, remainder in RDX.
  do-divide
  (sys.lap-x86:idiv64 :rcx)
  (sys.lap-x86:push :rdx)
  ;; Attempt to convert quotient to a fixnum.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:imul64 :rax 8)
  (sys.lap-x86:jo quotient-bignum)
  (sys.lap-x86:mov64 :r8 :rax)
  done-quotient
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:sub64 :lsp 8)
  (sys.lap-x86:mov64 (:lsp) :r8)
  ;; Attempt to convert remainder to a fixnum.
  (sys.lap-x86:mov64 :rax (:csp))
  (sys.lap-x86:imul64 :rax 8)
  (sys.lap-x86:jo remainder-bignum)
  (sys.lap-x86:mov64 :r9 :rax)
  done-remainder
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:add64 :lsp 8)
  (sys.lap-x86:mov32 :ecx 16)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret)
  ;; Allocate a bignum for the quotient in RCX.
  quotient-bignum
  (sys.lap-x86:mov64 :rax :rcx)
  (sys.lap-x86:mov64 :r13 (:constant %%make-bignum-64-rax))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  (sys.lap-x86:jmp done-quotient)
  ;; Allocate a bignum for the quotient in RCX.
  remainder-bignum
  (sys.lap-x86:mov64 :rax (:csp))
  (sys.lap-x86:mov64 :r13 (:constant %%make-bignum-64-rax))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  (sys.lap-x86:mov64 :r9 :r8)
  (sys.lap-x86:jmp done-remainder)
  128-bit-number
  ;; 128 bit number, 64 bit quotient.
  (sys.lap-x86:mov64 :rax (:r8 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:mov64 :rdx (:r8 #.(+ (- +tag-array-like+) 16)))
  (sys.lap-x86:mov64 :rcx (:r9 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:jmp do-divide)
  not-implemented
  (sys.lap-x86:mov64 :r8 (:constant "Full bignum TRUNCATE not implemented."))
  (sys.lap-x86:mov64 :r13 (:constant error))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:push 0)
  (sys.lap-x86:call (:symbol-function :r13)))

(define-lap-function %%truncate-float ()
  ;; Unbox the float.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  ;; Convert to unboxed integer.
  (sys.lap-x86:cvttss2si64 :rax :xmm0)
  ;; Box fixnum.
  (sys.lap-x86:lea64 :r8 ((:rax 8)))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-truncate (number divisor)
  (check-type number real)
  (check-type divisor real)
  (assert (/= divisor 0) (number divisor) 'division-by-zero)
  ;; Avoid overflow when doing fixnum arithmetic.
  ;; ????
  (when (and (eq divisor -1)
             (integerp number))
    (return-from generic-truncate
      (values (- number) 0)))
  (cond ((and (fixnump number)
              (fixnump divisor))
         (error "FIXNUM/FIXNUM case hit GENERIC-TRUNCATE"))
        ((and (fixnump number)
              (bignump divisor))
         (%%bignum-truncate (%make-bignum-from-fixnum number)
                            divisor))
        ((and (bignump number)
              (fixnump divisor))
         (%%bignum-truncate number
                            (%make-bignum-from-fixnum divisor)))
        ((and (bignump number)
              (bignump divisor))
         (%%bignum-truncate number divisor))
        ((or (floatp number)
             (floatp divisor))
         (let* ((val (/ number divisor))
                (integer-part (if (< most-negative-fixnum
                                     val
                                     most-positive-fixnum)
                                  ;; Fits in a fixnum, convert quickly.
                                  (%%truncate-float val)
                                  ;; Grovel inside the float
                                  (multiple-value-bind (significand exponent)
                                      (integer-decode-float val)
                                    (ash significand exponent)))))
           (values integer-part (* (- val integer-part) divisor))))
        ((or (ratiop number)
             (ratiop divisor))
         (let ((val (/ number divisor)))
           (multiple-value-bind (quot rem)
               (truncate (numerator val) (denominator val))
             (values quot (/ rem (denominator val))))))
        (t (check-type number number)
           (check-type divisor number)
           (error "Argument combination ~S and ~S not supported." number divisor))))

(defun generic-rem (number divisor)
  (multiple-value-bind (quot rem)
      (generic-truncate number divisor)
    (declare (ignore quot))
    rem))

(defun mod (number divisor)
  (multiple-value-bind (quot rem)
      (floor number divisor)
    (declare (ignore quot))
    rem))

;;; From SBCL 1.0.55
(defun floor (number &optional (divisor 1))
  ;; If the numbers do not divide exactly and the result of
  ;; (/ NUMBER DIVISOR) would be negative then decrement the quotient
  ;; and augment the remainder by the divisor.
  (multiple-value-bind (tru rem) (truncate number divisor)
    (if (and (not (zerop rem))
             (if (minusp divisor)
                 (plusp number)
                 (minusp number)))
        (values (1- tru) (+ rem divisor))
        (values tru rem))))

(define-lap-function %%float-/ ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Divide.
  (sys.lap-x86:divss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun binary-/ (x y)
  (cond ((and (typep x 'integer)
              (typep y 'integer))
         (multiple-value-bind (quot rem)
             (truncate x y)
           (cond ((zerop rem)
                  ;; Remainder is zero, result is an integer.
                  quot)
                 (t ;; Remainder is non-zero, produce a ratio.
                  (let ((negative (if (minusp x)
                                      (not (minusp y))
                                      (minusp y)))
                        (gcd (gcd x y)))
                    (make-ratio (if negative
                                    (- (/ (abs x) gcd))
                                    (/ (abs x) gcd))
                                (/ (abs y) gcd)))))))
        ((or (complexp x)
             (complexp y))
         (complex (/ (+ (* (realpart x) (realpart y))
                        (* (imagpart x) (imagpart y)))
                     (+ (expt (realpart y) 2)
                        (expt (imagpart y) 2)))
                  (/ (- (* (imagpart x) (realpart y))
                        (* (realpart x) (imagpart y)))
                     (+ (expt (realpart y) 2)
                        (expt (imagpart y) 2)))))
        ((or (floatp x) (floatp y))
         (%%float-/ (float x) (float y)))
        ((or (ratiop x) (ratiop y))
         (/ (* (numerator x) (denominator y))
            (* (denominator x) (numerator y))))
        (t (error "Argument complex ~S and ~S not supported." x y))))

(define-lap-function %%bignum-+ ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:cmp32 :eax :edx)
  (sys.lap-x86:cmov32na :eax :edx)
  (sys.lap-x86:add32 :eax 1)
  (sys.lap-x86:jc bignum-overflow)
  (sys.lap-x86:push :rax)
  (sys.lap-x86:push 0)
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:mov64 :r8 :rax)
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ +array-type-shift+))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:lea64 :r10 (:r8 #.+tag-array-like+))
  (sys.lap-x86:popf)
  ;; Reread lengths.
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:mov64 :r9 (:lsp 8))
  (sys.lap-x86:add64 :lsp 16)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; X in r8. Y in r9. Result in r10.
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:xor64 :r11 :r11) ; CF save register.
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last)
  (sys.lap-x86:clc) ; Avoid setting low bits in r11.
  (sys.lap-x86:rcl64 :r11 1) ; Restore saved carry.
  (sys.lap-x86:adc64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:rcr64 :r11 1) ; Save carry.
  (sys.lap-x86:jmp loop)
  last
  (sys.lap-x86:clc) ; Avoid setting low bits in r11.
  (sys.lap-x86:rcl64 :r11 1) ; Restore saved carry.
  (sys.lap-x86:adc64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:jo sign-changed)
  ;; Sign didn't change.
  (sys.lap-x86:sar64 :rsi 63)
  sign-fixed
  (sys.lap-x86:mov64 (:r10 #.(+ (- +tag-array-like+) 8) :rbx) :rsi)
  (sys.lap-x86:mov64 :r8 :r10)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13))
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume)
  sign-changed
  (sys.lap-x86:rcr64 :rsi 1)
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sign-fixed)
  bignum-overflow
  (sys.lap-x86:push 0) ; align
  (sys.lap-x86:mov64 :r8 (:constant "Aiee! Bignum overflow."))
  (sys.lap-x86:mov64 :r13 (:constant error))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:call (:symbol-function :r13)))

(define-lap-function %%float-+ ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Add.
  (sys.lap-x86:addss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-+ (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-+"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-+ (%make-bignum-from-fixnum x) y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-+ x (%make-bignum-from-fixnum y)))
        ((and (bignump x)
              (bignump y))
         (%%bignum-+ x y))
        ((or (complexp x)
             (complexp y))
         (complex (+ (realpart x) (realpart y))
                  (+ (imagpart x) (imagpart y))))
        ((or (floatp x)
             (floatp y))
         ;; Convert both arguments to the same kind of float.
         (let ((x* (if (floatp y)
                       (float x y)
                       x))
               (y* (if (floatp x)
                       (float y x)
                       y)))
           (%%float-+ x* y*)))
        ((or (ratiop x)
             (ratiop y))
         (/ (+ (* (numerator x) (denominator y))
               (* (numerator y) (denominator x)))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(define-lap-function %%bignum-- ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rax :rdx)
  (sys.lap-x86:add32 :eax 1)
  (sys.lap-x86:jc bignum-overflow)
  (sys.lap-x86:push :rax)
  (sys.lap-x86:push 0)
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:mov64 :r8 :rax)
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ +array-type-shift+))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:lea64 :r10 (:r8 #.+tag-array-like+))
  (sys.lap-x86:popf)
  ;; Reread lengths.
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:mov64 :r9 (:lsp 8))
  (sys.lap-x86:add64 :lsp 16)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; X in r8. Y in r9. Result in r10.
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:xor64 :r11 :r11) ; CF save register.
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last)
  (sys.lap-x86:clc) ; Avoid setting low bits in r11.
  (sys.lap-x86:rcl64 :r11 1) ; Restore saved carry.
  (sys.lap-x86:sbb64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:rcr64 :r11 1) ; Save carry.
  (sys.lap-x86:jmp loop)
  last
  (sys.lap-x86:clc) ; Avoid setting low bits in r11.
  (sys.lap-x86:rcl64 :r11 1) ; Restore saved carry.
  (sys.lap-x86:sbb64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:jo sign-changed)
  ;; Sign didn't change.
  (sys.lap-x86:sar64 :rsi 63)
  sign-fixed
  (sys.lap-x86:mov64 (:r10 #.(+ (- +tag-array-like+) 8) :rbx) :rsi)
  (sys.lap-x86:mov64 :r8 :r10)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13))
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume)
  sign-changed
  (sys.lap-x86:cmc)
  (sys.lap-x86:rcr64 :rsi 1)
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sign-fixed)
  bignum-overflow
  (sys.lap-x86:push 0) ; align
  (sys.lap-x86:mov64 :r8 (:constant "Aiee! Bignum overflow."))
  (sys.lap-x86:mov64 :r13 (:constant error))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:call (:symbol-function :r13)))

(define-lap-function %%float-- ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Subtract.
  (sys.lap-x86:subss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-- (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC--"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-- (%make-bignum-from-fixnum x) y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-- x (%make-bignum-from-fixnum y)))
        ((and (bignump x)
              (bignump y))
         (%%bignum-- x y))
        ((or (complexp x)
             (complexp y))
         (complex (- (realpart x) (realpart y))
                  (- (imagpart x) (imagpart y))))
        ((or (floatp x)
             (floatp y))
         ;; Convert both arguments to the same kind of float.
         (let ((x* (if (floatp y)
                       (float x y)
                       x))
               (y* (if (floatp x)
                       (float y x)
                       y)))
           (%%float-- x* y*)))
        ((or (ratiop x)
             (ratiop y))
         (/ (- (* (numerator x) (denominator y))
               (* (numerator y) (denominator x)))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

;;; Unsigned multiply X & Y, must be of type (UNSIGNED-BYTE 64)
;;; This can be either a fixnum, a length-one bignum or a length-two bignum.
;;; Always returns an (UNSIGNED-BYTE 128) in a length-three bignum.
(define-lap-function %%bignum-multiply-step ()
  ;; Read X.
  (sys.lap-x86:test64 :r8 7)
  (sys.lap-x86:jnz read-bignum-x)
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 3)
  ;; Read Y.
  read-y
  (sys.lap-x86:test64 :r9 7)
  (sys.lap-x86:jnz read-bignum-y)
  (sys.lap-x86:mov64 :rcx :r9)
  (sys.lap-x86:shr64 :rcx 3)
  perform-multiply
  (sys.lap-x86:mul64 :rcx)
  ;; RDX:RAX holds the 128-bit result.
  ;; Prepare to allocate the result.
  (sys.lap-x86:push :rax) ; Low half.
  (sys.lap-x86:push :rdx) ; High half.
  (sys.lap-x86:pushf) ; Flags, also aligns stack correctly
  (sys.lap-x86:cli)
  ;; Allocate a 3 word bignum.
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r8 32) ; fixnum 4 (ugh)
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:mov64 (:r8) #.(logior (ash 3 8) (ash +array-type-bignum+ +array-type-shift+)))
  ;; pointer to value.
  (sys.lap-x86:or64 :r8 #.+tag-array-like+)
  ;; GC back on.
  (sys.lap-x86:popf)
  ;; Set values.
  (sys.lap-x86:mov64 (:r8 #.(+ (- +tag-array-like+) 24)) 0)
  (sys.lap-x86:pop (:r8 #.(+ (- +tag-array-like+) 16)))
  (sys.lap-x86:pop (:r8 #.(+ (- +tag-array-like+) 8)))
  ;; Single value return
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:ret)
  read-bignum-x
  (sys.lap-x86:mov64 :rax (:r8 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:jmp read-y)
  read-bignum-y
  (sys.lap-x86:mov64 :rcx (:r9 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:jmp perform-multiply))

(defun %%bignum-multiply-unsigned (a b)
  (assert (bignump a))
  (assert (bignump b))
  (let* ((digs (+ (%array-like-length a)
                  (%array-like-length b)
                  1))
         (c (%make-bignum-of-length digs)))
    (dotimes (i digs)
      (setf (%array-like-ref-unsigned-byte-64 c i) 0))
    (loop for ix from 0 below (%array-like-length a) do
         (let ((u 0)
               (pb (min (%array-like-length b)
                        (- digs ix))))
           (when (< pb 1)
             (return))
           (loop for iy from 0 to (1- pb) do
                (let ((r-hat (+ (%array-like-ref-unsigned-byte-64 c (+ iy ix))
                                (%%bignum-multiply-step
                                 (%array-like-ref-unsigned-byte-64 a ix)
                                 (%array-like-ref-unsigned-byte-64 b iy))
                                u)))
                  (setf (%array-like-ref-unsigned-byte-64 c (+ iy ix))
                        (ldb (byte 64 0) r-hat))
                  (setf u (ash r-hat -64))))
           (when (< (+ ix pb) digs)
             (setf (%array-like-ref-unsigned-byte-64 c (+ ix pb)) u))))
    (%%canonicalize-bignum c)))

(defun %%bignum-multiply-signed (a b)
  "Multiply two integers together. A and B can be bignums or fixnums."
  (let ((a-negative (< a 0))
        (b-negative (< b 0))
        (c nil))
    (when a-negative
      (setf a (- a)))
    (when b-negative
      (setf b (- b)))
    (when (fixnump a)
      (setf a (%make-bignum-from-fixnum a)))
    (when (fixnump b)
      (setf b (%make-bignum-from-fixnum b)))
    (setf c (%%bignum-multiply-unsigned a b))
    (when (not (eql a-negative b-negative))
      (setf c (- c)))
    c))

(define-lap-function %%float-* ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Multiply.
  (sys.lap-x86:mulss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun generic-* (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-*"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-multiply-signed x y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-multiply-signed x y))
        ((and (bignump x)
              (bignump y))
         (%%bignum-multiply-signed x y))
        ((or (complexp x)
             (complexp y))
         (complex (- (* (realpart x) (realpart y))
                     (* (imagpart x) (imagpart y)))
                  (+ (* (imagpart x) (realpart y))
                     (* (realpart x) (imagpart y)))))
        ((or (floatp x)
             (floatp y))
         ;; Convert both arguments to the same kind of float.
         (let ((x* (if (floatp y)
                       (float x y)
                       x))
               (y* (if (floatp x)
                       (float y x)
                       y)))
           (%%float-* x* y*)))
        ((or (ratiop x)
             (ratiop y))
         (/ (* (numerator x) (numerator y))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(define-lap-function %%bignum-logand ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:push :rcx)
  (sys.lap-x86:push 0)
  (sys.lap-x86:lea64 :r8 ((:rcx 8)))
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ +array-type-shift+))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:lea64 :r10 (:r8 #.+tag-array-like+))
  (sys.lap-x86:popf)
  ;; Reread lengths.
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:mov64 :r9 (:lsp 8))
  (sys.lap-x86:add64 :lsp 16)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; X in r8. Y in r9. Result in r10.
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last)
  (sys.lap-x86:and64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:jmp loop)
  last
  (sys.lap-x86:and64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:mov64 :r8 :r10)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13))
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume))

(defun generic-logand (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-LOGAND"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-logand (%make-bignum-from-fixnum x) y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-logand x (%make-bignum-from-fixnum y)))
        ((and (bignump x)
              (bignump y))
         (%%bignum-logand x y))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination not supported."))))

(define-lap-function %%bignum-logior ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:mov64 :rcx :rax) ; rcx = len1
  (sys.lap-x86:cmp64 :rax :rdx) ; rdx = len2
  (sys.lap-x86:cmov64ng :rcx :rdx) ; rcx = !(len1 > len2) ? len2 : len1
  (sys.lap-x86:push :rcx)
  (sys.lap-x86:push 0)
  (sys.lap-x86:lea64 :r8 ((:rcx 8)))
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ +array-type-shift+))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:lea64 :r10 (:r8 #.+tag-array-like+))
  (sys.lap-x86:popf)
  ;; Reread lengths.
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:mov64 :r9 (:lsp 8))
  (sys.lap-x86:add64 :lsp 16)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; X in r8. Y in r9. Result in r10.
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last)
  (sys.lap-x86:or64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:jmp loop)
  last
  (sys.lap-x86:or64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:mov64 :r8 :r10)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13))
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume))

(defun generic-logior (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-LOGIOR"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-logior (%make-bignum-from-fixnum x) y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-logior x (%make-bignum-from-fixnum y)))
        ((and (bignump x)
              (bignump y))
         (%%bignum-logior x y))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination not supported."))))


(define-lap-function %%bignum-logxor ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  ;; Read lengths.
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:push :rcx)
  (sys.lap-x86:push 0)
  (sys.lap-x86:lea64 :r8 ((:rcx 8)))
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ +array-type-shift+))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:lea64 :r10 (:r8 #.+tag-array-like+))
  (sys.lap-x86:popf)
  ;; Reread lengths.
  (sys.lap-x86:mov64 :r8 (:lsp))
  (sys.lap-x86:mov64 :r9 (:lsp 8))
  (sys.lap-x86:add64 :lsp 16)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
  (sys.lap-x86:shr64 :rdx 8)
  ;; X in r8. Y in r9. Result in r10.
  ;; Pick the longest length.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:cmp64 :rax :rdx)
  (sys.lap-x86:cmov64ng :rcx :rdx)
  (sys.lap-x86:xor64 :rbx :rbx) ; offset
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:shl64 :rdx 3)
  loop
  (sys.lap-x86:cmp64 :rbx :rax)
  (sys.lap-x86:jae sx-left)
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-left-resume
  (sys.lap-x86:cmp64 :rbx :rdx)
  (sys.lap-x86:jae sx-right)
  (sys.lap-x86:mov64 :rdi (:r9 #.(+ (- +tag-array-like+) 8) :rbx))
  sx-right-resume
  (sys.lap-x86:add64 :rbx 8)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jz last)
  (sys.lap-x86:xor64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:jmp loop)
  last
  (sys.lap-x86:xor64 :rsi :rdi)
  (sys.lap-x86:mov64 (:r10 #.(- +tag-array-like+) :rbx) :rsi)
  (sys.lap-x86:mov64 :r8 :r10)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13))
  sx-left
  ;; Sign extend the left argument.
  ;; Previous value is not in RSI. Pull from the last word in the bignum.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) :rax))
  (sys.lap-x86:sar64 :rsi 63)
  (sys.lap-x86:jmp sx-left-resume)
  sx-right
  ;; Sign extend the right argument (previous value in RDI).
  (sys.lap-x86:sar64 :rdi 63)
  (sys.lap-x86:jmp sx-right-resume))

(defun generic-logxor (x y)
  (cond ((and (fixnump x)
              (fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-LOGXOR"))
        ((and (fixnump x)
              (bignump y))
         (%%bignum-logxor (%make-bignum-from-fixnum x) y))
        ((and (bignump x)
              (fixnump y))
         (%%bignum-logxor x (%make-bignum-from-fixnum y)))
        ((and (bignump x)
              (bignump y))
         (%%bignum-logxor x y))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination not supported."))))

(define-lap-function %%bignum-left-shift ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
    ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:mov64 :r8 :rax)
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 24) ; one word for the header, one extra, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 32) ; one word for the header, one extra, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:mov64 :r9 (:lsp))
  (sys.lap-x86:mov64 :rbx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:add64 :rbx #.(ash 1 8))
  (sys.lap-x86:mov64 (:r8) :rbx)
  (sys.lap-x86:sub64 :rbx #.(ash 1 8))
  (sys.lap-x86:add64 :r8 #.+tag-array-like+)
  (sys.lap-x86:popf)
  ;; R8: dest
  ;; R9: src
  ;; CL: count
  ;; RBX: n words.
  ;; R10: current word.
  (sys.lap-x86:mov64 :rcx (:lsp 8))
  (sys.lap-x86:sar64 :rcx 3)
  (sys.lap-x86:shr64 :rbx 8)
  (sys.lap-x86:mov32 :r10d 1)
  loop
  (sys.lap-x86:cmp64 :r10 :rbx)
  (sys.lap-x86:jae last-word)
  (sys.lap-x86:mov64 :rax (:r9 #.(+ (- +tag-array-like+) 8) (:r10 8)))
  (sys.lap-x86:mov64 :rdx (:r9 #.(+ (- +tag-array-like+)) (:r10 8)))
  (sys.lap-x86:shld64 :rax :rdx :cl)
  (sys.lap-x86:mov64 (:r8 #.(+ (- +tag-array-like+) 8) (:r10 8)) :rax)
  (sys.lap-x86:add64 :r10 1)
  (sys.lap-x86:jmp loop)
  last-word
  (sys.lap-x86:mov64 :rax (:r9 #.(- +tag-array-like+) (:rbx 8)))
  (sys.lap-x86:cqo)
  (sys.lap-x86:shld64 :rdx :rax :cl)
  (sys.lap-x86:mov64 (:r8 #.(+ (- +tag-array-like+) 8) (:rbx 8)) :rdx)
  (sys.lap-x86:mov64 :rax (:r9 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:shl64 :rax :cl)
  (sys.lap-x86:mov64 (:r8 #.(+ (- +tag-array-like+) 8)) :rax)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13)))

(define-lap-function %%bignum-right-shift ()
  ;; Save on the lisp stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:mov64 (:lsp -16) nil)
  (sys.lap-x86:sub64 :lsp 16)
  (sys.lap-x86:mov64 (:lsp) :r8)
  (sys.lap-x86:mov64 (:lsp 8) :r9)
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8)
    ;; Allocate a new bignum large enough to hold the result.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  (sys.lap-x86:shl64 :rax 3)
  (sys.lap-x86:mov64 :r8 :rax)
  (sys.lap-x86:test64 :r8 8)
  (sys.lap-x86:jz count-even)
  (sys.lap-x86:add64 :r8 8) ; one word for the header, no alignment.
  (sys.lap-x86:jmp do-allocate)
  count-even
  (sys.lap-x86:add64 :r8 16) ; one word for the header, one word for alignment.
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov64 :rcx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Set the header.
  (sys.lap-x86:mov64 :r9 (:lsp))
  (sys.lap-x86:mov64 :rbx (:r9 #.(- +tag-array-like+)))
  (sys.lap-x86:mov64 (:r8) :rbx)
  (sys.lap-x86:add64 :r8 #.+tag-array-like+)
  (sys.lap-x86:popf)
  ;; R8: dest
  ;; R9: src
  ;; CL: count (raw)
  ;; RBX: n words. (fixnum)
  ;; R10: current word. (fixnum)
  (sys.lap-x86:mov64 :rcx (:lsp 8))
  (sys.lap-x86:sar64 :rcx 3)
  (sys.lap-x86:and64 :rbx #.(lognot #xFF))
  (sys.lap-x86:shr64 :rbx 5)
  (sys.lap-x86:mov32 :r10d 8)
  loop
  (sys.lap-x86:cmp64 :r10 :rbx)
  (sys.lap-x86:jae last-word)
  ;; current+1
  (sys.lap-x86:mov64 :rax (:r9 #.(+ (- +tag-array-like+) 8) :r10))
  ;; current
  (sys.lap-x86:mov64 :rdx (:r9 #.(- +tag-array-like+) :r10))
  (sys.lap-x86:shrd64 :rdx :rax :cl)
  (sys.lap-x86:mov64 (:r8 #.(- +tag-array-like+) :r10) :rdx)
  (sys.lap-x86:add64 :r10 8)
  (sys.lap-x86:jmp loop)
  last-word
  (sys.lap-x86:mov64 :rax (:r9 #.(- +tag-array-like+) :rbx))
  (sys.lap-x86:sar64 :rax :cl)
  (sys.lap-x86:mov64 (:r8 #.(- +tag-array-like+) :rbx) :rax)
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :r13 (:constant %%canonicalize-bignum))
  (sys.lap-x86:jmp (:symbol-function :r13)))

(defun %ash (integer count)
  (cond ((not (fixnump count))
         (check-type count integer)
         (error "TODO: Bignum ASH count not implemented yet."))
        ((bignump integer)
         (cond
           ((plusp count)
            (multiple-value-bind (quot rem)
                (truncate count 32)
              (dotimes (i quot)
                (setf integer (%%bignum-left-shift integer 32)))
              (%%bignum-left-shift integer rem)))
           ((minusp count)
            (setf count (- count))
            (multiple-value-bind (quot rem)
                (truncate count 32)
              (dotimes (i quot)
                (setf integer (%%bignum-right-shift integer 32))
                (cond ((eql integer 0) (return-from %ash 0))
                      ((fixnump integer)
                       (setf integer (%make-bignum-from-fixnum integer)))))
              (%%bignum-right-shift integer rem)))
           (t integer)))
        (t (check-type integer integer)
           (ash integer count))))

(defun abs (number)
  (check-type number number)
  (etypecase number
    (complex (sqrt (+ (expt (realpart number) 2)
                      (expt (imagpart number) 2))))
    (real (if (minusp number)
              (- number)
              number))))

(define-lap-function %%float-sqrt ()
  ;; Unbox the float.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  ;; Sqrt.
  (sys.lap-x86:sqrtss :xmm0 :xmm0)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.+tag-single-float+))
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret))

(defun sqrt (number)
  (check-type number number)
  (etypecase number
    (real (%%float-sqrt (float number)))))

;;; Convert a bignum to canonical form.
;;; If it can be represented as a fixnum it is converted,
;;; otherwise it is converted to the shortest possible bignum
;;; by removing redundant sign-extension bits.
(define-lap-function %%canonicalize-bignum ()
  (sys.lap-x86:mov64 :rax (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rax 8) ; RAX = number of fragments (raw).
  ;; Zero-size bignums are zero.
  (sys.lap-x86:jz return-zero)
  ;; Read the sign bit.
  (sys.lap-x86:mov64 :rcx (:r8 #.(- +tag-array-like+) (:rax 8)))
  (sys.lap-x86:sar64 :rcx 63) ; rcx = sign-extended sign-bit.
  crunch-loop
  (sys.lap-x86:cmp64 :rax 1)
  (sys.lap-x86:je maybe-fixnumize)
  ;; Read the last fragment.
  (sys.lap-x86:mov64 :rsi (:r8 #.(- +tag-array-like+) (:rax 8)))
  ;; Compare against the extended sign bit.
  ;; Finish if they're not equal.
  (sys.lap-x86:cmp64 :rsi :rcx)
  (sys.lap-x86:jne maybe-resize-bignum)
  ;; Read the sign bit of the second-to-last fragment
  (sys.lap-x86:mov64 :rsi (:r8 #.(+ (- +tag-array-like+) -8) (:rax 8)))
  (sys.lap-x86:sar64 :rsi 63)
  ;; Compare against the original sign bit. If equal, then this
  ;; fragment can be dropped.
  (sys.lap-x86:cmp64 :rsi :rcx)
  (sys.lap-x86:jne maybe-resize-bignum)
  (sys.lap-x86:sub64 :rax 1)
  (sys.lap-x86:jmp crunch-loop)
  ;; Final size of the bignum has been determined.
  maybe-resize-bignum
  ;; Test if the size actually changed.
  (sys.lap-x86:mov64 :rdx (:r8 #.(- +tag-array-like+)))
  (sys.lap-x86:shr64 :rdx 8)
  (sys.lap-x86:cmp64 :rax :rdx)
  ;; If it didn't change, return the original bignum.
  ;; TODO: eventually the bignum code will pass in stack-allocated
  ;; bignum objects, this'll have to allocate anyway...
  (sys.lap-x86:je do-return)
  ;; Resizing.
  (sys.lap-x86:pushf)
  (sys.lap-x86:cli)
  ;; Align control stack and save the new size.
  (sys.lap-x86:push :rax)
  (sys.lap-x86:push 0)
  ;; Save the original bignum on the data stack.
  (sys.lap-x86:mov64 (:lsp -8) nil)
  (sys.lap-x86:sub64 :lsp 8)
  (sys.lap-x86:mov64 (:lsp) :r8)
  ;; Convert new size (in rax) to fixnum.
  (sys.lap-x86:shl64 :rax 3)
  ;; Add in the header and any alignment required.
  (sys.lap-x86:test64 :rax 8)
  (sys.lap-x86:jz adjust-even)
  (sys.lap-x86:lea64 :r8 (:rax 8))
  (sys.lap-x86:jmp do-allocate)
  adjust-even
  (sys.lap-x86:lea64 :r8 (:rax 16))
  do-allocate
  (sys.lap-x86:mov64 :r9 (:constant :static))
  (sys.lap-x86:mov32 :ecx 16)
  (sys.lap-x86:mov64 :r13 (:constant %raw-allocate))
  (sys.lap-x86:call (:symbol-function :r13))
  (sys.lap-x86:mov64 :lsp :rbx)
  ;; fixnum to pointer.
  (sys.lap-x86:sar64 :r8 3)
  ;; Restore new size.
  (sys.lap-x86:pop :rax)
  (sys.lap-x86:pop :rax)
  ;; Set the header.
  (sys.lap-x86:mov64 :rcx :rax)
  (sys.lap-x86:shl64 :rax 8)
  (sys.lap-x86:or64 :rax #.(ash +array-type-bignum+ 3))
  (sys.lap-x86:mov64 (:r8) :rax)
  (sys.lap-x86:or64 :r8 #.+tag-array-like+)
  (sys.lap-x86:popf)
  ;; Fetch the original bignum.
  (sys.lap-x86:mov64 :r9 (:lsp))
  (sys.lap-x86:add64 :lsp 8)
  ;; Copy words, we know there will always be at least one.
  copy-loop
  (sys.lap-x86:mov64 :rax (:r9 #.(- +tag-array-like+) (:rcx 8)))
  (sys.lap-x86:mov64 (:r8 #.(- +tag-array-like+) (:rcx 8)) :rax)
  (sys.lap-x86:sub64 :rcx 1)
  (sys.lap-x86:jnz copy-loop)
  do-return
  (sys.lap-x86:mov32 :ecx 8)
  (sys.lap-x86:mov64 :rbx :lsp)
  (sys.lap-x86:ret)
  ;; Attempt to convert a size-1 bignum to a fixnum.
  maybe-fixnumize
  (sys.lap-x86:mov64 :rdx (:r8 #.(+ (- +tag-array-like+) 8)))
  (sys.lap-x86:imul64 :rdx 8)
  (sys.lap-x86:jo maybe-resize-bignum)
  (sys.lap-x86:mov64 :r8 :rdx)
  (sys.lap-x86:jmp do-return)
  return-zero
  (sys.lap-x86:xor32 :r8d :r8d)
  (sys.lap-x86:jmp do-return))

(defun generic-lognot (integer)
  (logxor integer -1))

(defun integer-length (integer)
  (when (minusp integer) (setf integer (- integer)))
  (do ((len 0 (1+ len)))
      ((zerop integer)
       len)
    (setf integer (ash integer -1))))

(defun logandc1 (integer-1 integer-2)
  "AND complement of INTEGER-1 with INTEGER-2."
  (logand (lognot integer-1) integer-2))

(defun logandc2 (integer-1 integer-2)
  "AND INTEGER-1 with complement of INTEGER-2."
  (logand integer-1 (lognot integer-2)))

(defun lognand (integer-1 integer-2)
  "Complement of INTEGER-1 AND INTEGER-2."
  (lognot (logand integer-1 integer-2)))

(defun lognor (integer-1 integer-2)
  "Complement of INTEGER-1 OR INTEGER-2."
  (lognot (logior integer-1 integer-2)))

(defun logorc1 (integer-1 integer-2)
  "OR complement of INTEGER-1 with INTEGER-2."
  (logior (lognot integer-1) integer-2))

(defun logorc2 (integer-1 integer-2)
  "OR INTEGER-1 with complement of INTEGER-2."
  (logior integer-1 (lognot integer-2)))

(defconstant boole-1 'boole-1 "integer-1")
(defconstant boole-2 'boole-2 "integer-2")
(defconstant boole-andc1 'boole-andc1 "and complement of integer-1 with integer-2")
(defconstant boole-andc2 'boole-andc2 "and integer-1 with complement of integer-2")
(defconstant boole-and 'boole-and "and")
(defconstant boole-c1 'boole-c1 "complement of integer-1")
(defconstant boole-c2 'boole-c2 "complement of integer-2")
(defconstant boole-clr 'boole-clr "always 0 (all zero bits)")
(defconstant boole-eqv 'boole-eqv "equivalence (exclusive nor)")
(defconstant boole-ior 'boole-ior "inclusive or")
(defconstant boole-nand 'boole-nand "not-and")
(defconstant boole-nor 'boole-nor "not-or")
(defconstant boole-orc1 'boole-orc1 "or complement of integer-1 with integer-2")
(defconstant boole-orc2 'boole-orc2 "or integer-1 with complement of integer-2")
(defconstant boole-set 'boole-set "always -1 (all one bits)")
(defconstant boole-xor 'boole-xor "exclusive or")

(defun boole (op integer-1 integer-2)
  "Perform bit-wise logical OP on INTEGER-1 and INTEGER-2."
  (ecase op
    (boole-1 integer-1)
    (boole-2 integer-2)
    (boole-andc1 (logandc1 integer-1 integer-2))
    (boole-andc2 (logandc2 integer-1 integer-2))
    (boole-and (logand integer-1 integer-2))
    (boole-c1 (lognot integer-1))
    (boole-c2 (lognot integer-2))
    (boole-clr 0)
    (boole-eqv (logeqv integer-1 integer-2))
    (boole-ior (logior integer-1 integer-2))
    (boole-nand (lognand integer-1 integer-2))
    (boole-nor (lognor integer-1 integer-2))
    (boole-orc1 (logorc1 integer-1 integer-2))
    (boole-orc2 (logorc2 integer-1 integer-2))
    (boole-set -1)
    (boole-xor (logxor integer-1 integer-2))))

(defun signum (number)
  (if (zerop number)
      number
      (/ number (abs number))))

;; From SBCL 1.0.55
(defun round (number &optional (divisor 1))
  "Rounds number (or number/divisor) to nearest integer.
  The second returned value is the remainder."
  (multiple-value-bind (tru rem) (truncate number divisor)
    (if (zerop rem)
        (values tru rem)
        (let ((thresh (/ (abs divisor) 2)))
          (cond ((or (> rem thresh)
                     (and (= rem thresh) (oddp tru)))
                 (if (minusp divisor)
                     (values (- tru 1) (+ rem divisor))
                     (values (+ tru 1) (- rem divisor))))
                ((let ((-thresh (- thresh)))
                   (or (< rem -thresh)
                       (and (= rem -thresh) (oddp tru))))
                 (if (minusp divisor)
                     (values (+ tru 1) (- rem divisor))
                     (values (- tru 1) (+ rem divisor))))
                (t (values tru rem)))))))

;;; Mathematical horrors!

(defconstant pi 3.14159265359)

;;; http://devmaster.net/forums/topic/4648-fast-and-accurate-sinecosine/
(defun sin (x)
  (setf x (- (mod (+ x pi) (* 2 pi)) pi))
  (let* ((b (/ 4 (float pi 0.0)))
         (c (/ -4 (* (float pi 0.0) (float pi 0.0))))
         (y (+ (* b x) (* c x (abs x))))
         (p 0.225))
    (+ (* p (- (* y (abs y)) y)) y)))

(defun cos (x)
  (sin (+ x (/ pi 2))))

;;; http://en.literateprograms.org/Logarithm_Function_(Python)
(defun log-e (x)
  (let ((base 2.71828)
        (epsilon 0.000000000001)
        (integer 0)
        (partial 0.5)
        (decimal 0.0))
    (loop (when (>= x 1) (return))
       (decf integer)
       (setf x (* x base)))
    (loop (when (< x base) (return))
       (incf integer)
       (setf x (/ x base)))
    (setf x (* x x))
    (loop (when (<= partial epsilon) (return))
       (when (>= x base) ;If X >= base then a_k is 1
         (incf decimal partial) ;Insert partial to the front of the list
         (setf x (/ x base))) ;Since a_k is 1, we divide the number by the base
       (setf partial (* partial 0.5))
       (setf x (* x x)))
    (+ integer decimal)))

(defun log (number &optional base)
  (if base
      (/ (log number) (log base))
      (log-e number)))

;;; http://forums.devshed.com/c-programming-42/implementing-an-atan-function-200106.html
(defun atan (number1 &optional number2)
  (if number2
      (atan2 number1 number2)
      (let ((x number1)
            (y 0.0))
        (when (zerop number1)
          (return-from atan 0))
        (when (< x 0)
          (return-from atan (- (atan (- x)))))
        (setf x (/ (- x 1.0) (+ x 1.0))
              y (* x x))
        (setf x (* (+ (* (- (* (+ (* (- (* (+ (* (- (* (+ (* (- (* 0.0028662257 y) 0.0161657367) y) 0.0429096138) y) 0.0752896400) y) 0.1065626393) y) 0.1420889944) y) 0.1999355085) y) 0.3333314528) y) 1) x))
        (setf x (+ 0.785398163397 x))
        x)))

(defun atan2 (y x)
  (cond ((> x 0) (atan (/ y x)))
        ((and (>= y 0) (< x 0))
         (+ (atan (/ y x)) pi))
        ((and (< y 0) (< x 0))
         (- (atan (/ y x)) pi))
        ((and (> y 0) (zerop x))
         (/ pi 2))
        ((and (< y 0) (zerop x))
         (- (/ pi 2)))
        (t 0)))

(defun two-arg-gcd (a b)
  (check-type a integer)
  (check-type b integer)
  (setf a (abs a))
  (setf b (abs b))
  (loop (when (zerop b)
          (return a))
     (psetf b (mod a b)
            a b)))

(defun gcd (&rest integers)
  (declare (dynamic-extent integers))
  (cond
    ((endp integers) 0)
    ((endp (rest integers))
     (check-type (first integers) integer)
     (abs (first integers)))
    (t (reduce #'two-arg-gcd integers))))
