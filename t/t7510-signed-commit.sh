#!/bin/sh

test_description='signed commit tests'
. ./test-lib.sh
GNUPGHOME_NOT_USED=$GNUPGHOME
. "$TEST_DIRECTORY/lib-gpg.sh"

test_expect_success GPG 'create signed commits' '
	test_when_finished "test_unconfig commit.gpgsign" &&

	echo 1 >file && git add file &&
	test_tick && git commit -S -m initial &&
	git tag initial &&
	git branch side &&

	echo 2 >file && test_tick && git commit -a -S -m second &&
	git tag second &&

	git checkout side &&
	echo 3 >elif && git add elif &&
	test_tick && git commit -m "third on side" &&

	git checkout master &&
	test_tick && git merge -S side &&
	git tag merge &&

	echo 4 >file && test_tick && git commit -a -m "fourth unsigned" &&
	git tag fourth-unsigned &&

	test_tick && git commit --amend -S -m "fourth signed" &&
	git tag fourth-signed &&

	git config commit.gpgsign true &&
	echo 5 >file && test_tick && git commit -a -m "fifth signed" &&
	git tag fifth-signed &&

	git config commit.gpgsign false &&
	echo 6 >file && test_tick && git commit -a -m "sixth" &&
	git tag sixth-unsigned &&

	git config commit.gpgsign true &&
	echo 7 >file && test_tick && git commit -a -m "seventh" --no-gpg-sign &&
	git tag seventh-unsigned &&

	test_tick && git rebase -f HEAD^^ && git tag sixth-signed HEAD^ &&
	git tag seventh-signed &&

	echo 8 >file && test_tick && git commit -a -m eighth -SB7227189 &&
	git tag eighth-signed-alt &&

	# commit.gpgsign is still on but this must not be signed
	git tag ninth-unsigned $(echo 9 | git commit-tree HEAD^{tree}) &&
	# explicit -S of course must sign.
	git tag tenth-signed $(echo 9 | git commit-tree -S HEAD^{tree})
'

test_expect_success GPG 'verify and show signatures' '
	(
		for commit in initial second merge fourth-signed \
			fifth-signed sixth-signed seventh-signed tenth-signed
		do
			git verify-commit $commit &&
			git show --pretty=short --show-signature $commit >actual &&
			grep "Good signature from" actual &&
			! grep "BAD signature from" actual &&
			echo $commit OK || exit 1
		done
	) &&
	(
		for commit in merge^2 fourth-unsigned sixth-unsigned \
			seventh-unsigned ninth-unsigned
		do
			test_must_fail git verify-commit $commit &&
			git show --pretty=short --show-signature $commit >actual &&
			! grep "Good signature from" actual &&
			! grep "BAD signature from" actual &&
			echo $commit OK || exit 1
		done
	) &&
	(
		for commit in eighth-signed-alt
		do
			git show --pretty=short --show-signature $commit >actual &&
			grep "Good signature from" actual &&
			! grep "BAD signature from" actual &&
			grep "not certified" actual &&
			echo $commit OK || exit 1
		done
	)
'

test_expect_success GPG 'verify-commit exits success on untrusted signature' '
	git verify-commit eighth-signed-alt 2>actual &&
	grep "Good signature from" actual &&
	! grep "BAD signature from" actual &&
	grep "not certified" actual
'

test_expect_success GPG 'verify signatures with --raw' '
	(
		for commit in initial second merge fourth-signed fifth-signed sixth-signed seventh-signed
		do
			git verify-commit --raw $commit 2>actual &&
			grep "GOODSIG" actual &&
			! grep "BADSIG" actual &&
			echo $commit OK || exit 1
		done
	) &&
	(
		for commit in merge^2 fourth-unsigned sixth-unsigned seventh-unsigned
		do
			test_must_fail git verify-commit --raw $commit 2>actual &&
			! grep "GOODSIG" actual &&
			! grep "BADSIG" actual &&
			echo $commit OK || exit 1
		done
	) &&
	(
		for commit in eighth-signed-alt
		do
			git verify-commit --raw $commit 2>actual &&
			grep "GOODSIG" actual &&
			! grep "BADSIG" actual &&
			grep "TRUST_UNDEFINED" actual &&
			echo $commit OK || exit 1
		done
	)
'

test_expect_success GPG 'show signed commit with signature' '
	git show -s initial >commit &&
	git show -s --show-signature initial >show &&
	git verify-commit -v initial >verify.1 2>verify.2 &&
	git cat-file commit initial >cat &&
	grep -v -e "gpg: " -e "Warning: " show >show.commit &&
	grep -e "gpg: " -e "Warning: " show >show.gpg &&
	grep -v "^ " cat | grep -v "^gpgsig " >cat.commit &&
	test_cmp show.commit commit &&
	test_cmp show.gpg verify.2 &&
	test_cmp cat.commit verify.1
'

test_expect_success GPG 'detect fudged signature' '
	git cat-file commit seventh-signed >raw &&
	sed -e "s/^seventh/7th forged/" raw >forged1 &&
	git hash-object -w -t commit forged1 >forged1.commit &&
	test_must_fail git verify-commit $(cat forged1.commit) &&
	git show --pretty=short --show-signature $(cat forged1.commit) >actual1 &&
	grep "BAD signature from" actual1 &&
	! grep "Good signature from" actual1
'

test_expect_success GPG 'detect fudged signature with NUL' '
	git cat-file commit seventh-signed >raw &&
	cat raw >forged2 &&
	echo Qwik | tr "Q" "\000" >>forged2 &&
	git hash-object -w -t commit forged2 >forged2.commit &&
	test_must_fail git verify-commit $(cat forged2.commit) &&
	git show --pretty=short --show-signature $(cat forged2.commit) >actual2 &&
	grep "BAD signature from" actual2 &&
	! grep "Good signature from" actual2
'

test_expect_success GPG 'amending already signed commit' '
	git checkout fourth-signed^0 &&
	git commit --amend -S --no-edit &&
	git verify-commit HEAD &&
	git show -s --show-signature HEAD >actual &&
	grep "Good signature from" actual &&
	! grep "BAD signature from" actual
'

test_expect_success GPG 'show custom format fields for signed commit if gpg is missing' '
	cat >expect <<-\EOF &&
	N




	Y
	EOF
	test_config gpg.program this-is-not-a-program &&
	git log -n1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" sixth-signed >actual 2>/dev/null &&
	test_cmp expect actual
'

test_expect_success GPG 'show custom format fields for unsigned commit if gpg is missing' '
	cat >expect <<-\EOF &&
	N




	N
	EOF
	test_config gpg.program this-is-not-a-program &&
	git log -n1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" seventh-unsigned >actual 2>/dev/null &&
	test_cmp expect actual
'

test_expect_success GPG 'show error for custom format fields on signed commit if gpg is missing' '
	test_config gpg.program this-is-not-a-program &&
	git log -n1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" sixth-signed >/dev/null 2>errors &&
	test $(wc -l <errors) = 1 &&
	test_i18ngrep "^error: " errors &&
	grep this-is-not-a-program errors
'

test_expect_success GPG 'do not run gpg at all for unsigned commit' '
	test_config gpg.program this-is-not-a-program &&
	git log -n1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" seventh-unsigned >/dev/null 2>errors &&
	test_must_be_empty errors
'

test_expect_success GPG 'show good signature with custom format' '
	cat >expect <<-\EOF &&
	G
	13B6F51ECDDE430D
	C O Mitter <committer@example.com>
	73D758744BE721698EC54E8713B6F51ECDDE430D
	73D758744BE721698EC54E8713B6F51ECDDE430D
	Y
	EOF
	git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" sixth-signed >actual &&
	test_cmp expect actual
'

test_expect_success GPG 'show bad signature with custom format' '
	cat >expect <<-\EOF &&
	B
	13B6F51ECDDE430D
	C O Mitter <committer@example.com>


	Y
	EOF
	git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" $(cat forged1.commit) >actual &&
	test_cmp expect actual
'

test_expect_success GPG 'show untrusted signature with custom format' '
	cat >expect <<-\EOF &&
	U
	65A0EEA02E30CAD7
	Eris Discordia <discord@example.net>
	F8364A59E07FFE9F4D63005A65A0EEA02E30CAD7
	D4BE22311AD3131E5EDA29A461092E85B7227189
	Y
	EOF
	git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" eighth-signed-alt >actual &&
	test_cmp expect actual
'

test_expect_success GPG 'show unknown signature with custom format' '
	cat >expect <<-\EOF &&
	E
	65A0EEA02E30CAD7



	Y
	EOF
	GNUPGHOME="$GNUPGHOME_NOT_USED" git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" eighth-signed-alt >actual &&
	test_cmp expect actual
'

test_expect_success GPG 'show lack of signature with custom format' '
	cat >expect <<-\EOF &&
	N




	N
	EOF
	git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP%n%G+" seventh-unsigned >actual &&
	test_cmp expect actual
'

test_expect_success GPG 'show lack of raw signature with custom format' '
	git log -1 --format=format:"%GR" seventh-unsigned > actual &&
	test_must_be_empty actual
'

test_expect_success GPG 'show lack of raw signature with custom format without running GPG' '
	echo N > expected &&
	test_config gpg.program this-is-not-a-program &&
	git log -1 --format="%G+%GR" seventh-unsigned >actual 2>errors &&
	test_cmp expected actual &&
	test_must_be_empty errors
'

test_expect_success GPG 'show raw signature with custom format' '
	git log -1 --format=format:"%GR" sixth-signed >output &&
	cat output &&
	head -n1 output | grep -q "^---*BEGIN PGP SIGNATURE---*$" &&
	sed 1d output | grep -q "^$" &&
	sed "1,/^$/d" output | grep -q "^[a-zA-Z0-9+/][a-zA-Z0-9+/=]*$" &&
	tail -n2 output | head -n1 | grep -q "^=[a-zA-Z0-9+/][a-zA-Z0-9+/=]*$" &&
	tail -n1 output | grep -q "^---*END PGP SIGNATURE---*$"
'

test_expect_success GPG 'show raw signature with custom format without running GPG' '
	test_config gpg.program this-is-not-a-program &&
	git log -1 --format=format:"%GR" sixth-signed >rawsig 2>errors &&
	cat rawsig &&
	head -n1 rawsig | grep -q "^---*BEGIN PGP SIGNATURE---*$" &&
	sed 1d rawsig | grep -q "^$" &&
	sed "1,/^$/d" rawsig | grep -q "^[a-zA-Z0-9+/][a-zA-Z0-9+/=]*$" &&
	tail -n2 rawsig | head -n1 | grep -q "^=[a-zA-Z0-9+/][a-zA-Z0-9+/=]*$" &&
	tail -n1 rawsig | grep -q "^---*END PGP SIGNATURE---*$" &&
	test_must_be_empty errors
'

test_expect_success GPG 'show presence of gpgsig with custom format when gpg is missing without errors' '
	echo Y > expected &&
	git log -1 --format=%G+ sixth-signed >output 2>errors &&
	test_cmp expected output &&
	test_must_be_empty errors
'

test_expect_success GPG 'show presence of invalid gpgsig header' '
	printf gpgsig >gpgsig-header &&
	tee prank-signature <<-\EOF | sed "s/^/ /" >>gpgsig-header &&
	this is not a signature but an awful...
					   888
					   888
					   888
	88888b.  888d888  8888b.  88888b.  888  888
	888 "88b 888P"       "88b 888 "88b 888 .88P
	888  888 888     .d888888 888  888 888888K
	888 d88P 888     888  888 888  888 888 "88b
	88888P"  888     "Y888888 888  888 888  888
	888
	888
	888
	EOF
	git cat-file commit seventh-unsigned >bare-commit-data &&
	sed "/^committer/r gpgsig-header" bare-commit-data >commit-data &&
	git hash-object -w -t commit commit-data >commit &&
	echo Y >expected &&
	cat prank-signature >>expected &&
	git log -n1 --format=format:%G+%n%GR $(cat commit) >actual 2>errors &&
	test_cmp expected actual &&
	test_must_be_empty errors
'

test_expect_success GPG 'log.showsignature behaves like --show-signature' '
	test_config log.showsignature true &&
	git show initial >actual &&
	grep "gpg: Signature made" actual &&
	grep "gpg: Good signature" actual
'

test_expect_success GPG 'check config gpg.format values' '
	test_config gpg.format openpgp &&
	git commit -S --amend -m "success" &&
	test_config gpg.format OpEnPgP &&
	test_must_fail git commit -S --amend -m "fail"
'

test_expect_success GPG 'detect fudged commit with double signature' '
	sed -e "/gpgsig/,/END PGP/d" forged1 >double-base &&
	sed -n -e "/gpgsig/,/END PGP/p" forged1 | \
		sed -e "s/^gpgsig//;s/^ //" | gpg --dearmor >double-sig1.sig &&
	gpg -o double-sig2.sig -u 29472784 --detach-sign double-base &&
	cat double-sig1.sig double-sig2.sig | gpg --enarmor >double-combined.asc &&
	sed -e "s/^\(-.*\)ARMORED FILE/\1SIGNATURE/;1s/^/gpgsig /;2,\$s/^/ /" \
		double-combined.asc > double-gpgsig &&
	sed -e "/committer/r double-gpgsig" double-base >double-commit &&
	git hash-object -w -t commit double-commit >double-commit.commit &&
	test_must_fail git verify-commit $(cat double-commit.commit) &&
	git show --pretty=short --show-signature $(cat double-commit.commit) >double-actual &&
	grep "BAD signature from" double-actual &&
	grep "Good signature from" double-actual
'

test_expect_success GPG 'show double signature with custom format' '
	cat >expect <<-\EOF &&
	E




	EOF
	git log -1 --format="%G?%n%GK%n%GS%n%GF%n%GP" $(cat double-commit.commit) >actual &&
	test_cmp expect actual
'

test_done
