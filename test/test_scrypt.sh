#!/bin/sh

# File locations (allowing flexible out-of-tree builds)
scrypt_binary=$1
test_scrypt_binary=$2
reference_txt=$3
reference_enc=$4

# Constants
password="hunter2"
known_values="known_values.txt"
encrypted_file="attempt.enc"
decrypted_file="attempt.txt"
decrypted_reference_file="attempt_reference.txt"
out_valgrind="test-valgrind"

# Check for parameters
if [ -z $scrypt_binary ] || [ -z $test_scrypt_binary ] || \
    [ -z $reference_txt ] || [ -z $reference_enc ]; then
	printf "Error: Scrypt binary, test binary, good file, or good "
	echo "encrypted file not given."
	echo "Attempting to use default values for in-source-tree build."
	scrypt_binary="../scrypt"
	test_scrypt_binary="./test_scrypt"
	reference_txt="./test_scrypt.good"
	reference_enc="./test_scrypt_good.enc"
fi
if [ ! -f $scrypt_binary ] || [ ! -f $test_scrypt_binary ] || \
    [ ! -f $reference_txt ] || [ ! -f $reference_enc ]; then
	echo "Error: Cannot find at least one required file."
	exit 1
fi

# Check for optional commands
if [ -z "$USE_VALGRIND" ]; then
	USE_VALGRIND="0"
fi
if [ "$USE_VALGRIND" -gt 0 ]; then
	if ! command -v valgrind >/dev/null 2>&1; then
		echo "valgrind not detected: disabling memory checking"
		USE_VALGRIND="0"
	fi
fi

setup_valgrind_cmd() {
	basename=$1
	valgrind_disable_number=$2

	# Set up valgrind command (if requested)
	if [ "$USE_VALGRIND" -gt "$valgrind_disable_number" ]; then
		valgrind_cmd="valgrind --log-file=$out_valgrind/$basename.val \
			--leak-check=full --show-leak-kinds=all \
			--error-exitcode=1 "
	else
		valgrind_cmd=""
	fi

	# return to calling function
	echo "$valgrind_cmd"
}

notify_success_fail() {
	basename=$1
	retval=$2
	cmd_retval=$3

	if [ "$retval" -eq 0 ]; then
		echo "PASSED!"
	else
		echo "FAILED"
		if [ "$USE_VALGRIND" -gt 0 ] && [ "$cmd_retval" -gt 0 ]; then
			echo "Valgrind detected a memory failure!"
			cat "$out_valgrind/$basename.val"
		fi
	fi
}

##################################################

# Test functions
test_known_values() {
	basename="01-generate-known-test-values"
	printf "Running test: $basename... "

	# Set up valgrind command (if requested), $test_scrypt_binary requires
	# a lot of memory, so valgrind is only enabled if $USE_VALGRIND > 1.
	valgrind_cmd=$( setup_valgrind_cmd $basename 1 )

	# Run actual test command
	$valgrind_cmd $test_scrypt_binary > $known_values
	cmd_retval=$?

	# Check results
	retval=$cmd_retval

	# The generated values should match the known good values.
	if cmp -s $known_values $reference_txt; then
		rm $known_values
	else
		retval=1
	fi

	# Print PASS or FAIL, and return result
	notify_success_fail $basename $retval $cmd_retval
	return "$retval"
}

test_encrypt_file() {
	basename="02-encrypt-a-file"
	printf "Running test: $basename... "

	# Set up valgrind command (if requested)
	valgrind_cmd=$( setup_valgrind_cmd $basename 0 )

	# Run actual test command
	echo $password | $valgrind_cmd $scrypt_binary enc -P $reference_txt \
		$encrypted_file
	cmd_retval=$?

	# Check results
	retval=$cmd_retval

	# The encrypted file should be different from the original file.  We
	# cannot check against the "reference" encrypted file, because
	# encrypted files include random salt.  If successful, don't delete
	# $encrypted_file yet; we need it for the next test.
	if cmp -s $encrypted_file $reference_txt; then
		retval=1
	fi

	# Print PASS or FAIL, and return result
	notify_success_fail $basename $retval $cmd_retval
	return "$retval"
}

test_decrypt_file() {
	basename="03-decrypt-a-file"
	printf "Running test: $basename... "

	# Set up valgrind command (if requested)
	valgrind_cmd=$( setup_valgrind_cmd $basename 0 )

	# Run actual test command
	echo $password | $valgrind_cmd $scrypt_binary dec -P $encrypted_file \
		$decrypted_file
	cmd_retval=$?

	# Check results
	retval=$cmd_retval

	# The decrypted file should match the reference.
	if cmp -s $decrypted_file $reference_txt; then
		# clean up
		rm $encrypted_file
		rm $decrypted_file
	else
		retval=1
	fi

	# Print PASS or FAIL, and return result
	notify_success_fail $basename $retval $cmd_retval
	return "$retval"
}

test_decrypt_reference_file() {
	basename="04-decrypt-a-reference-encrypted-file"
	printf "Running test: $basename... "

	# Set up valgrind command (if requested)
	valgrind_cmd=$( setup_valgrind_cmd $basename 0 )

	# Run actual test command
	echo $password | $valgrind_cmd $scrypt_binary dec -P $reference_enc \
		$decrypted_reference_file
	cmd_retval=$?

	# Check results
	retval=$cmd_retval

	# The decrypted reference file should match the reference.
	if cmp -s $decrypted_reference_file $reference_txt; then
		rm $decrypted_reference_file
	else
		retval=1
	fi

	# Print PASS or FAIL, and return result
	notify_success_fail $basename $retval $cmd_retval
	return "$retval"
}


##################################################

# Clean up previous valgrind (if in use)
if [ "$USE_VALGRIND" -gt 0 ]; then
	rm -rf $out_valgrind
	mkdir $out_valgrind
fi

# Run tests
test_known_values &&			\
	test_encrypt_file &&		\
	test_decrypt_file &&		\
	test_decrypt_reference_file	\

# Return value to Makefile
exit $?

