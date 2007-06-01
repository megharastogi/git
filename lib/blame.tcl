# git-gui blame viewer
# Copyright (C) 2006, 2007 Shawn Pearce

class blame {

field commit  ; # input commit to blame
field path    ; # input filename to view in $commit

field w
field w_line
field w_cgrp
field w_load
field w_file
field w_cmit
field status

field highlight_line   -1 ; # current line selected
field highlight_commit {} ; # sha1 of commit selected

field total_lines       0  ; # total length of file
field blame_lines       0  ; # number of lines computed
field commit_count      0  ; # number of commits in $commit_list
field commit_list      {}  ; # list of commit sha1 in receipt order
field order                ; # array commit -> receipt order
field header               ; # array commit,key -> header field
field line_commit          ; # array line -> sha1 commit
field line_file            ; # array line -> file name

field r_commit      ; # commit currently being parsed
field r_orig_line   ; # original line number
field r_final_line  ; # final line number
field r_line_count  ; # lines in this region

field tooltip_wm     {} ; # Current tooltip toplevel, if open
field tooltip_timer  {} ; # Current timer event for our tooltip
field tooltip_commit {} ; # Commit in tooltip
field tooltip_text   {} ; # Text in current tooltip

variable active_color #98e1a0
variable group_colors {
	#cbcbcb
	#e1e1e1
}

constructor new {i_commit i_path} {
	variable active_color
	global cursor_ptr

	set commit $i_commit
	set path   $i_path

	make_toplevel top w
	wm title $top "[appname] ([reponame]): File Viewer"
	set status "Loading $commit:$path..."

	label $w.path -text "$commit:$path" \
		-anchor w \
		-justify left \
		-borderwidth 1 \
		-relief sunken \
		-font font_uibold
	pack $w.path -side top -fill x

	frame $w.out
	set w_load $w.out.loaded_t
	text $w_load \
		-background white -borderwidth 0 \
		-state disabled \
		-wrap none \
		-height 40 \
		-width 1 \
		-font font_diff
	$w_load tag conf annotated -background grey

	set w_line $w.out.linenumber_t
	text $w_line \
		-background white -borderwidth 0 \
		-state disabled \
		-wrap none \
		-height 40 \
		-width 5 \
		-font font_diff
	$w_line tag conf linenumber -justify right

	set w_cgrp $w.out.commit_t
	text $w_cgrp \
		-background white -borderwidth 0 \
		-state disabled \
		-wrap none \
		-height 40 \
		-width 4 \
		-font font_diff

	set w_file $w.out.file_t
	text $w_file \
		-background white -borderwidth 0 \
		-state disabled \
		-wrap none \
		-height 40 \
		-width 80 \
		-xscrollcommand [list $w.out.sbx set] \
		-font font_diff

	scrollbar $w.out.sbx -orient h -command [list $w_file xview]
	scrollbar $w.out.sby -orient v \
		-command [list scrollbar2many [list \
		$w_load \
		$w_line \
		$w_cgrp \
		$w_file \
		] yview]
	grid \
		$w_cgrp \
		$w_line \
		$w_load \
		$w_file \
		$w.out.sby \
		-sticky nsew
	grid conf $w.out.sbx -column 3 -sticky we
	grid columnconfigure $w.out 3 -weight 1
	grid rowconfigure $w.out 0 -weight 1
	pack $w.out -fill both -expand 1

	label $w.status \
		-textvariable @status \
		-anchor w \
		-justify left \
		-borderwidth 1 \
		-relief sunken
	pack $w.status -side bottom -fill x

	frame $w.cm
	set w_cmit $w.cm.t
	text $w_cmit \
		-background white -borderwidth 0 \
		-state disabled \
		-wrap none \
		-height 10 \
		-width 80 \
		-xscrollcommand [list $w.cm.sbx set] \
		-yscrollcommand [list $w.cm.sby set] \
		-font font_diff
	$w_cmit tag conf header_key \
		-tabs {3c} \
		-background $active_color \
		-font font_uibold
	$w_cmit tag conf header_val \
		-background $active_color \
		-font font_ui
	$w_cmit tag raise sel
	scrollbar $w.cm.sbx -orient h -command [list $w_cmit xview]
	scrollbar $w.cm.sby -orient v -command [list $w_cmit yview]
	pack $w.cm.sby -side right -fill y
	pack $w.cm.sbx -side bottom -fill x
	pack $w_cmit -expand 1 -fill both
	pack $w.cm -side bottom -fill x

	menu $w.ctxm -tearoff 0
	$w.ctxm add command \
		-label "Copy Commit" \
		-command [cb _copycommit]

	foreach i [list \
		$w_cgrp \
		$w_load \
		$w_line \
		$w_file] {
		$i conf -cursor $cursor_ptr
		$i conf -yscrollcommand \
			[list many2scrollbar [list \
			$w_cgrp \
			$w_load \
			$w_line \
			$w_file \
			] yview $w.out.sby]
		bind $i <Button-1> "
			[cb _hide_tooltip]
			[cb _click $i @%x,%y]
			focus $i
		"
		bind $i <Any-Motion>  [cb _show_tooltip $i @%x,%y]
		bind $i <Any-Enter>   [cb _hide_tooltip]
		bind $i <Any-Leave>   [cb _hide_tooltip]
		bind_button3 $i "
			[cb _hide_tooltip]
			set cursorX %x
			set cursorY %y
			set cursorW %W
			tk_popup $w.ctxm %X %Y
		"
	}

	foreach i [list \
		$w_cgrp \
		$w_load \
		$w_line \
		$w_file \
		$w_cmit] {
		bind $i <Key-Up>        {catch {%W yview scroll -1 units};break}
		bind $i <Key-Down>      {catch {%W yview scroll  1 units};break}
		bind $i <Key-Left>      {catch {%W xview scroll -1 units};break}
		bind $i <Key-Right>     {catch {%W xview scroll  1 units};break}
		bind $i <Key-k>         {catch {%W yview scroll -1 units};break}
		bind $i <Key-j>         {catch {%W yview scroll  1 units};break}
		bind $i <Key-h>         {catch {%W xview scroll -1 units};break}
		bind $i <Key-l>         {catch {%W xview scroll  1 units};break}
		bind $i <Control-Key-b> {catch {%W yview scroll -1 pages};break}
		bind $i <Control-Key-f> {catch {%W yview scroll  1 pages};break}
	}

	bind $w_cmit <Button-1> [list focus $w_cmit]
	bind $top <Visibility> [list focus $top]
	bind $top <Destroy> [list delete_this $this]

	if {$commit eq {}} {
		set fd [open $path r]
	} else {
		set cmd [list git cat-file blob "$commit:$path"]
		set fd [open "| $cmd" r]
	}
	fconfigure $fd -blocking 0 -translation lf -encoding binary
	fileevent $fd readable [cb _read_file $fd]
}

method _read_file {fd} {
	$w_load conf -state normal
	$w_cgrp conf -state normal
	$w_line conf -state normal
	$w_file conf -state normal
	while {[gets $fd line] >= 0} {
		regsub "\r\$" $line {} line
		incr total_lines

		if {$total_lines > 1} {
			$w_load insert end "\n"
			$w_cgrp insert end "\n"
			$w_line insert end "\n"
			$w_file insert end "\n"
		}

		$w_line insert end "$total_lines" linenumber
		$w_file insert end "$line"
	}
	$w_load conf -state disabled
	$w_cgrp conf -state disabled
	$w_line conf -state disabled
	$w_file conf -state disabled

	if {[eof $fd]} {
		close $fd
		_status $this
		set cmd [list git blame -M -C --incremental]
		if {$commit eq {}} {
			lappend cmd --contents $path
		} else {
			lappend cmd $commit
		}
		lappend cmd -- $path
		set fd [open "| $cmd" r]
		fconfigure $fd -blocking 0 -translation lf -encoding binary
		fileevent $fd readable [cb _read_blame $fd]
	}
} ifdeleted { catch {close $fd} }

method _read_blame {fd} {
	variable group_colors

	$w_cgrp conf -state normal
	while {[gets $fd line] >= 0} {
		if {[regexp {^([a-z0-9]{40}) (\d+) (\d+) (\d+)$} $line line \
			cmit original_line final_line line_count]} {
			set r_commit     $cmit
			set r_orig_line  $original_line
			set r_final_line $final_line
			set r_line_count $line_count

			if {[catch {set g $order($cmit)}]} {
				set bg [lindex $group_colors 0]
				set group_colors [lrange $group_colors 1 end]
				lappend group_colors $bg

				$w_cgrp tag conf g$cmit -background $bg
				$w_line tag conf g$cmit -background $bg
				$w_file tag conf g$cmit -background $bg

				set order($cmit) $commit_count
				incr commit_count
				lappend commit_list $cmit
			}
		} elseif {[string match {filename *} $line]} {
			set file [string range $line 9 end]
			set n    $r_line_count
			set lno  $r_final_line
			set cmit $r_commit

			if {[regexp {^0{40}$} $cmit]} {
				set abbr work
			} else {
				set abbr [string range $cmit 0 4]
			}

			if {![catch {set ncmit $line_commit([expr {$lno - 1}])}]} {
				if {$ncmit eq $cmit} {
					set abbr |
				}
			}

			while {$n > 0} {
				set lno_e "$lno.0 lineend + 1c"
				if {[catch {set g g$line_commit($lno)}]} {
					$w_load tag add annotated $lno.0 $lno_e
				} else {
					$w_cgrp tag remove g$g $lno.0 $lno_e
					$w_line tag remove g$g $lno.0 $lno_e
					$w_file tag remove g$g $lno.0 $lno_e

					$w_cgrp tag remove a$g $lno.0 $lno_e
					$w_line tag remove a$g $lno.0 $lno_e
					$w_file tag remove a$g $lno.0 $lno_e
				}

				set line_commit($lno) $cmit
				set line_file($lno)   $file

				$w_cgrp delete $lno.0 "$lno.0 lineend"
				$w_cgrp insert $lno.0 $abbr
				set abbr |

				$w_cgrp tag add g$cmit $lno.0 $lno_e
				$w_line tag add g$cmit $lno.0 $lno_e
				$w_file tag add g$cmit $lno.0 $lno_e

				$w_cgrp tag add a$cmit $lno.0 $lno_e
				$w_line tag add a$cmit $lno.0 $lno_e
				$w_file tag add a$cmit $lno.0 $lno_e

				if {$highlight_line == -1} {
					if {[lindex [$w_file yview] 0] == 0} {
						$w_file see $lno.0
						_showcommit $this $lno
					}
				} elseif {$highlight_line == $lno} {
					_showcommit $this $lno
				}

				incr n -1
				incr lno
				incr blame_lines
			}

			if {![catch {set ncmit $line_commit($lno)}]} {
				if {$ncmit eq $cmit} {
					$w_cgrp delete $lno.0 "$lno.0 lineend + 1c"
					$w_cgrp insert $lno.0 "|\n"
				}
			}
		} elseif {[regexp {^([a-z-]+) (.*)$} $line line key data]} {
			set header($r_commit,$key) $data
		}
	}
	$w_cgrp conf -state disabled

	if {[eof $fd]} {
		close $fd
		set status {Annotation complete.}
	} else {
		_status $this
	}
} ifdeleted { catch {close $fd} }

method _status {} {
	set have  $blame_lines
	set total $total_lines
	set pdone 0
	if {$total} {set pdone [expr {100 * $have / $total}]}

	set status [format \
		"Loading annotations... %i of %i lines annotated (%2i%%)" \
		$have $total $pdone]
}

method _click {cur_w pos} {
	set lno [lindex [split [$cur_w index $pos] .] 0]
	if {$lno eq {}} return
	_showcommit $this $lno
}

method _showcommit {lno} {
	global repo_config
	variable active_color

	if {$highlight_commit ne {}} {
		set cmit $highlight_commit
		$w_cgrp tag conf a$cmit -background {}
		$w_line tag conf a$cmit -background {}
		$w_file tag conf a$cmit -background {}
	}

	$w_cmit conf -state normal
	$w_cmit delete 0.0 end
	if {[catch {set cmit $line_commit($lno)}]} {
		set cmit {}
		$w_cmit insert end "Loading annotation..."
	} else {
		$w_cgrp tag conf a$cmit -background $active_color
		$w_line tag conf a$cmit -background $active_color
		$w_file tag conf a$cmit -background $active_color

		set author_name {}
		set author_email {}
		set author_time {}
		catch {set author_name $header($cmit,author)}
		catch {set author_email $header($cmit,author-mail)}
		catch {set author_time [clock format \
			$header($cmit,author-time) \
			-format {%Y-%m-%d %H:%M:%S}
		]}

		set committer_name {}
		set committer_email {}
		set committer_time {}
		catch {set committer_name $header($cmit,committer)}
		catch {set committer_email $header($cmit,committer-mail)}
		catch {set committer_time [clock format \
			$header($cmit,committer-time) \
			-format {%Y-%m-%d %H:%M:%S}
		]}

		if {[catch {set msg $header($cmit,message)}]} {
			set msg {}
			catch {
				set fd [open "| git cat-file commit $cmit" r]
				fconfigure $fd -encoding binary -translation lf
				if {[catch {set enc $repo_config(i18n.commitencoding)}]} {
					set enc utf-8
				}
				while {[gets $fd line] > 0} {
					if {[string match {encoding *} $line]} {
						set enc [string tolower [string range $line 9 end]]
					}
				}
				set msg [encoding convertfrom $enc [read $fd]]
				set msg [string trim $msg]
				close $fd

				set author_name [encoding convertfrom $enc $author_name]
				set committer_name [encoding convertfrom $enc $committer_name]

				set header($cmit,author) $author_name
				set header($cmit,committer) $committer_name
			}
			set header($cmit,message) $msg
		}

		$w_cmit insert end "commit $cmit\n" header_key
		$w_cmit insert end "Author:\t" header_key
		$w_cmit insert end "$author_name $author_email" header_val
		$w_cmit insert end "$author_time\n" header_val

		$w_cmit insert end "Committer:\t" header_key
		$w_cmit insert end "$committer_name $committer_email" header_val
		$w_cmit insert end "$committer_time\n" header_val

		if {$line_file($lno) ne $path} {
			$w_cmit insert end "Original File:\t" header_key
			$w_cmit insert end "[escape_path $line_file($lno)]\n" header_val
		}

		$w_cmit insert end "\n$msg"
	}
	$w_cmit conf -state disabled

	set highlight_line $lno
	set highlight_commit $cmit

	if {$highlight_commit eq $tooltip_commit} {
		_hide_tooltip $this
	}
}

method _copycommit {} {
	set pos @$::cursorX,$::cursorY
	set lno [lindex [split [$::cursorW index $pos] .] 0]
	if {![catch {set commit $line_commit($lno)}]} {
		clipboard clear
		clipboard append \
			-format STRING \
			-type STRING \
			-- $commit
	}
}

method _show_tooltip {cur_w pos} {
	set lno [lindex [split [$cur_w index $pos] .] 0]
	if {[catch {set cmit $line_commit($lno)}]} {
		_hide_tooltip $this
		return
	}

	if {$cmit eq $highlight_commit} {
		_hide_tooltip $this
		return
	}

	if {$cmit eq $tooltip_commit} {
		_position_tooltip $this
	} elseif {$tooltip_wm ne {}} {
		_open_tooltip $this $cur_w
	} elseif {$tooltip_timer eq {}} {
		set tooltip_timer [after 1000 [cb _open_tooltip $cur_w]]
	}
}

method _open_tooltip {cur_w} {
	set tooltip_timer {}
	set pos_x [winfo pointerx $cur_w]
	set pos_y [winfo pointery $cur_w]
	if {[winfo containing $pos_x $pos_y] ne $cur_w} {
		_hide_tooltip $this
		return
	}

	set pos @[join [list \
		[expr {$pos_x - [winfo rootx $cur_w]}] \
		[expr {$pos_y - [winfo rooty $cur_w]}]] ,]
	set lno [lindex [split [$cur_w index $pos] .] 0]
	set cmit $line_commit($lno)

	set author_name {}
	set author_email {}
	set author_time {}
	catch {set author_name $header($cmit,author)}
	catch {set author_email $header($cmit,author-mail)}
	catch {set author_time [clock format \
		$header($cmit,author-time) \
		-format {%Y-%m-%d %H:%M:%S}
	]}

	set committer_name {}
	set committer_email {}
	set committer_time {}
	catch {set committer_name $header($cmit,committer)}
	catch {set committer_email $header($cmit,committer-mail)}
	catch {set committer_time [clock format \
		$header($cmit,committer-time) \
		-format {%Y-%m-%d %H:%M:%S}
	]}

	set summary {}
	catch {set summary $header($cmit,summary)}

	set tooltip_commit $cmit
	set tooltip_text "commit $cmit
$author_name $author_email  $author_time
$summary"

	if {$tooltip_wm ne "$cur_w.tooltip"} {
		_hide_tooltip $this

		set tooltip_wm [toplevel $cur_w.tooltip -borderwidth 1]
		wm overrideredirect $tooltip_wm 1
		wm transient $tooltip_wm [winfo toplevel $cur_w]
		pack [label $tooltip_wm.label \
			-background lightyellow \
			-foreground black \
			-textvariable @tooltip_text \
			-justify left]
	}
	_position_tooltip $this
}

method _position_tooltip {} {
	set req_w [winfo reqwidth  $tooltip_wm.label]
	set req_h [winfo reqheight $tooltip_wm.label]
	set pos_x [expr {[winfo pointerx .] +  5}]
	set pos_y [expr {[winfo pointery .] + 10}]

	set g "${req_w}x${req_h}"
	if {$pos_x >= 0} {append g +}
	append g $pos_x
	if {$pos_y >= 0} {append g +}
	append g $pos_y

	wm geometry $tooltip_wm $g
	raise $tooltip_wm
}

method _hide_tooltip {} {
	if {$tooltip_wm ne {}} {
		destroy $tooltip_wm
		set tooltip_wm {}
		set tooltip_commit {}
	}
	if {$tooltip_timer ne {}} {
		after cancel $tooltip_timer
		set tooltip_timer {}
	}
}

}
