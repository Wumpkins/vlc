#!/bin/bash
(set -o igncr) 2>/dev/null && set -o igncr; # this comment is required

# Regression testing script for VLC
# Step through a list of files
#  Compile, run, and check the output of each expected-to-work test
#  Compile and check the error of each expected-to-fail test

NVCC="nvcc"

VLC="sudo vlc -c"

globallog=./tests/test.log
rm -f $globallog
error=0
globalerror=0
NC='\033[0m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
keep=0
pass=0
fail=0
Usage() {
    echo "Usage: test.sh [options] [.mc files]"
    echo "-k    Keep intermediate files"
    echo "-h    Print this help"
    exit 1
}

SignalError() {
    if [ $error -eq 0 ] ; then
	echo "FAILED"
	error=1
    fi
    echo "  $1"
}

# Compare <outfile> <reffile> <difffile>
# Compares the outfile with reffile.  Differences, if any, written to difffile
Compare() {
    generatedfiles="$generatedfiles $3"
    echo diff -b $1 $2 ">" $3 1>&2
    diff -b "$1" "$2" > "$3" 2>&1 || {
	SignalError "$1 differs"
	echo "FAILED $1 differs from $2" 1>&2
    }
}

# Run <args>
# Report the command, run it, and report any errors
Run() {
    echo $* 1>&2
    eval $* || {
	SignalError "$1 failed on $*"
	return 1
    }
}

# RunFail <args>
# Report the command, run it, and expect an error
RunFail() {
    echo $* 1>&2
    eval $* && {
	SignalError "failed: $* did not report an error"
	return 1
    }
    return 0
}

Check() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.vlc//'`
     reffile=`echo $1 | sed 's/.vlc$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename " 1>&2

    generatedfiles=""

    generatedfiles="$generatedfiles ./tests/${basename}.cu ./tests/${basename}.out ./tests/${basename}" &&
    Run "$VLC" $1 "> null" &&
    Run "$NVCC" "./tests/${basename}.cu -o ./tests/${basename} && ./tests/${basename}" ">" "./tests/${basename}.out" &&
    Compare ./tests/${basename}.out ./${reffile}.out ./tests/${basename}.diff

    if [ $error -eq 0 ] ; then
	if [ $keep -eq 0 ] ; then
	    rm -f $generatedfiles
	fi
	echo "OK"
	echo "###### SUCCESS" 1>&2
	((pass++))
    else
	echo "###### FAILED" 1>&2
	globalerror=$error
	((fail++))
    fi
    echo -n "$basename 2"

}

CheckFail() {
     error=0
     basename=`echo $1 | sed 's/.*\\///
                              s/.vlc//'`

     echo -n "$basename..."

     echo 1>&2
     echo "###### Testing $basename " 1>&2

     generatedfiles=""

     generatedfiles="$generatedfiles ./${basename}.out ./${basename}.diff" &&
     RunFail "$VLC" $1 "2>" "${basename}.out" ">>" $globallog &&
     Compare "tests/$basename.vlc.err" "./${basename}.out" "./${basename}.diff"

     # Report the status and clean up the generated files

     if [ $error -eq 0 ] ; then
 	if [ $keep -eq 0 ] ; then
	    rm -f $generatedfiles
 	fi
 	echo "OK"
 	echo "###### SUCCESS" 1>&2
	((pass++))
     else
 	echo "###### FAILED" 1>&2
 	globalerror=$error
	((fail++))
     fi
    rm -f *.out
    rm -f *.diff
 }

while getopts kdpsh c; do
    case $c in
	k) # Keep intermediate files
	    keep=1
	    ;;
	h) # Help
	    Usage
	    ;;
    esac
done

shift `expr $OPTIND - 1`

if [ $# -ge 1 ]
then
    files=$@
else
    files="tests/test-*.vlc tests/fail-*.vlc"
fi

for file in $files
do
    case $file in
	*test-*)
	    Check $file 2>> $globallog
	    ;;
	*fail-*)
            CheckFail $file 2>> $globallog
	    ;;
	*)
	    echo "unknown file type $file"
	    globalerror=1
	    ;;
    esac
done
echo ""
echo -e "Tests Passed: $pass"
echo -e "Tests Failed: $fail"
exit $globalerror
