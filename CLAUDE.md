# Net::PublicSuffixList

A Perl module for working with the Mozilla Public Suffix List. It can
fetch the list from the network, read a local copy, or build a list by
hand with `add_suffix` and `remove_suffix`.

## Layout

* `lib/Net/PublicSuffixList.pm` is the whole module. `$VERSION` lives here.
* `Makefile.PL` is a modulino. Run it to build, or `require` it and call
  `arguments` to get the `WriteMakefile` data.
* `t/` holds the tests. `t/test_manifest` (Test::Manifest) sets which
  tests run and in what order, so a new test file must be added there.
* `xt/` holds author tests (`xt/citation.t`).
* `corpus/test.dat` is a small suffix list that `t/suffix.t` uses.
* `examples/` has sample scripts.
* `MANIFEST` lists the files in the distribution. Add new files to it.
* `Changes` is the change log.
* The GitHub workflows come from https://github.com/briandfoy/github_workflows.

## Perl and prerequisites

* The minimum Perl is v5.26 (`MIN_PERL_VERSION` in `Makefile.PL`,
  `use v5.26` in the module).
* The module uses subroutine signatures through
  `use experimental qw(signatures)`, along with postfix dereferencing
  and `state`.
* It needs Mojolicious 8 or later. `fetch_list_from_net` uses
  Mojo::UserAgent.

## Code style

* Indent with tabs.
* Closing braces are indented to the level of the block they close,
  not the level of the statement that opened it.

## Tests

* `prove -l t` runs the tests. So do `perl Makefile.PL` and `make test`.
* Network tests in `t/network.t` are skipped unless
  `NET_PUBLICSUFFIXLIST_NETWORK=1` is set.
* When the network tests run, they delete `t/cache` and rewrite
  `t/cache/public_suffix_list.dat`, which is listed in `MANIFEST`.
* Tests collect warnings through `$SIG{__WARN__}` and check them with
  `like`.

## Where the list came from

`$self->{source}` records where the list came from:

| Value        | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| `local_file` | read from `local_path`                                     |
| `net`        | fetched from the network                                   |
| `net_cached` | the server said 304 Not Modified, so read from `cache_dir` |

## Settled decisions; don't suggest changing these

* `use warnings;` followed by `no warnings;` in the module stays as it is.
* The `Mojo::Date->new( ... )` call in `fetch_list_from_net` is correct.
* `split_host`'s behavior for a host with no suffix, or a host that is
  itself a suffix, is not a bug.
* How `fetch_list_from_net` handles network failures is more complicated
  than it looks. Don't propose quick fixes for it.

## Committing

* Claude may commit in this repo when a person asks it to.
* Make Claude the author and brian d foy the co-author:

```bash
git commit --author="Claude <noreply@anthropic.com>" \
	-m "subject" \
	-m "Co-Authored-By: brian d foy <briandfoy@pobox.com>"
```

* Don't push.
