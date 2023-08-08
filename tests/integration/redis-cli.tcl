source tests/support/cli.tcl

if {$::singledb} {
    set ::dbnum 0
} else {
    set ::dbnum 9
}

start_server {tags {"cli"}} {
    proc open_cli {{opts ""} {infile ""}} {
        if { $opts == "" } {
            set opts "-n $::dbnum"
        }
        set ::env(TERM) dumb
        set cmdline [rediscli [srv host] [srv port] $opts]
        if {$infile ne ""} {
            set cmdline "$cmdline < $infile"
            set mode "r"
        } else {
            set mode "r+"
        }
        set fd [open "|$cmdline" $mode]
        fconfigure $fd -buffering none
        fconfigure $fd -blocking false
        fconfigure $fd -translation binary
        set _ $fd
    }

    proc close_cli {fd} {
        close $fd
    }

    proc read_cli {fd} {
        set ret [read $fd]
        while {[string length $ret] == 0} {
            after 10
            set ret [read $fd]
        }

        # We may have a short read, try to read some more.
        set empty_reads 0
        while {$empty_reads < 5} {
            set buf [read $fd]
            if {[string length $buf] == 0} {
                after 10
                incr empty_reads
            } else {
                append ret $buf
                set empty_reads 0
            }
        }
        return $ret
    }

    proc write_cli {fd buf} {
        puts $fd $buf
        flush $fd
    }

    # Helpers to run tests in interactive mode

    proc format_output {output} {
        set _ [string trimright $output "\n"]
    }

    proc run_command {fd cmd} {
        write_cli $fd $cmd
        set _ [format_output [read_cli $fd]]
    }

    proc test_interactive_cli {name code} {
        set ::env(FAKETTY) 1
        set fd [open_cli]
        test "Interactive CLI: $name" $code
        close_cli $fd
        unset ::env(FAKETTY)
    }

    proc test_interactive_cli_reverse_search {name code} {
        set ::env(FORCE_REVERSE_SEARCH_MODE) 1
        set ::env(FAKETTY) 1
        set fd [open_cli]
        test "Interactive CLI: $name" $code
        close_cli $fd
        unset ::env(FAKETTY)
        unset ::env(FORCE_REVERSE_SEARCH_MODE)
    }

    proc test_interactive_nontty_cli {name code} {
        set fd [open_cli]
        test "Interactive non-TTY CLI: $name" $code
        close_cli $fd
    }

    # Helpers to run tests where stdout is not a tty
    proc write_tmpfile {contents} {
        set tmp [tmpfile "cli"]
        set tmpfd [open $tmp "w"]
        puts -nonewline $tmpfd $contents
        close $tmpfd
        set _ $tmp
    }

    proc _run_cli {host port db opts args} {
        set cmd [rediscli $host $port [list -n $db {*}$args]]
        foreach {key value} $opts {
            if {$key eq "pipe"} {
                set cmd "sh -c \"$value | $cmd\""
            }
            if {$key eq "path"} {
                set cmd "$cmd < $value"
            }
        }

        set fd [open "|$cmd" "r"]
        fconfigure $fd -buffering none
        fconfigure $fd -translation binary
        set resp [read $fd 1048576]
        close $fd
        set _ [format_output $resp]
    }

    proc run_cli {args} {
        _run_cli [srv host] [srv port] $::dbnum {} {*}$args
    }

    proc run_cli_with_input_pipe {mode cmd args} {
        if {$mode == "x" } {
            _run_cli [srv host] [srv port] $::dbnum [list pipe $cmd] -x {*}$args
        } elseif {$mode == "X"} {
            _run_cli [srv host] [srv port] $::dbnum [list pipe $cmd] -X tag {*}$args
        }
    }

    proc run_cli_with_input_file {mode path args} {
        if {$mode == "x" } {
            _run_cli [srv host] [srv port] $::dbnum [list path $path] -x {*}$args
        } elseif {$mode == "X"} {
            _run_cli [srv host] [srv port] $::dbnum [list path $path] -X tag {*}$args
        }
    }

    proc run_cli_host_port_db {host port db args} {
        _run_cli $host $port $db {} {*}$args
    }

    proc test_nontty_cli {name code} {
        test "Non-interactive non-TTY CLI: $name" $code
    }

    # Helpers to run tests where stdout is a tty (fake it)
    proc test_tty_cli {name code} {
        set ::env(FAKETTY) 1
        test "Non-interactive TTY CLI: $name" $code
        unset ::env(FAKETTY)
    }

    test_interactive_cli_reverse_search "should a match" {
        run_command $fd "first command\r\n"
        run_command $fd "second command\r\n"

        set result [run_command $fd "f"]

        assert_equal 1 [string match {*\(reverse-i-search\)>*f*irst command*} $result]
    }

    test_interactive_cli_reverse_search "should find latest match if both match" {
        run_command $fd "first command\r\n"
        run_command $fd "second command\r\n"

        set result [run_command $fd "command"]

        assert_equal 1 [string match {*\(reverse-i-search\)>*second *command*} $result]
    }

    test_interactive_cli_reverse_search "should find a different match" {
        run_command $fd "first command\r\n"
        run_command $fd "second command\r\n"

        set result [run_command $fd "s"]

        assert_equal 1 [string match {*\(reverse-i-search\)>*s*econd command*} $result]
    }

    test_interactive_cli_reverse_search "should find no match" {
        run_command $fd "first command\r\n"
        run_command $fd "second command\r\n"

        set result [run_command $fd "blah"]

        assert_equal 1 [string match {*\(reverse-i-search\)>*blah*} $result]
    }
}