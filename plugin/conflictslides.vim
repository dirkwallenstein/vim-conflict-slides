" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU Lesser General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU Lesser General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.


if (exists("g:loaded_conflictslides") && g:loaded_conflictslides)
    finish
endif
let g:loaded_conflictslides = 1


let s:CONFLICT_MARKER_START = '<<<<<<<'
let s:CONFLICT_MARKER_END = '>>>>>>>'
let s:CONFLICT_MARKER_BASE = '|||||||'
let s:CONFLICT_MARKER_SEPARATOR = '======='


fun! s:EchoImportant(message)
    " Try to echo important messages as described in the Vim docs.
    redraw | echohl WarningMsg | echomsg a:message | echohl None
endf

fun! s:StringToCharList(string)
    " Split a string into a list of individual characters
    return split(a:string, '\zs')
endfun

fun! s:EnforceArgumentMembership(arguments, valid_arguments)
    " Ensure each item in the list a:arguments is present in
    " a:valid_arguments.  Skip empty arguments.
    for l:arg in a:arguments
        if empty(l:arg)
            continue
        endif
        if index(a:valid_arguments, l:arg) == -1
            echomsg "Allowed arguments: " . string(a:valid_arguments)
            throw "Invalid argument: " . l:arg
        endif
    endfor
endfun

fun! s:IsIn(member, member_list)
    " Test if a:member is in a:member_list
    if index(a:member_list, a:member) == -1
        return 0
    else
        return 1
    endif
endfun

" === Conflict Info ===

fun! s:GetCurrentConflictRange()
    " Find the range of the current conflict and
    " return [l:start_this, l:end_this]
    " return an empty list if not inside a conflict range
    let l:save_cursor = getpos(".")
    let l:on_start = 0
    let l:on_end = 0
    let l:pattern_start = '^' . s:CONFLICT_MARKER_START . '\( .*\|$\)'
    let l:pattern_end = '^' . s:CONFLICT_MARKER_END . '\( .*\|$\)'

    if getline('.') =~ l:pattern_start
        let l:start_this = line('.')
        let l:on_start = 1
    endif
    if getline('.') =~ l:pattern_end
        let l:end_this = line('.')
        let l:on_end = 1
    endif

    if !l:on_start
        let l:start_this = search(l:pattern_start, 'bnW')
        if l:start_this == 0
            return []
        endif

        if !l:on_end
            let l:end_previous = search(l:pattern_end, 'bnW')
            if l:end_previous != 0 && l:end_previous > l:start_this
                return []
            endif
        endif
    endif

    if !l:on_end
        let l:end_this = search(l:pattern_end, 'nW')
        if l:end_this == 0
            return []
        endif

        if !l:on_start
            let l:start_next = search(l:pattern_start, 'nW')
            if l:start_next != 0 && l:end_this > l:start_next
                return []
            endif
        endif
    endif

    call setpos('.', l:save_cursor)
    let l:found_range = [l:start_this, l:end_this]
    call s:EnforceValidContentRange(l:found_range, 0)
    return l:found_range
endf

fun! s:EnforceValidContentRange(range, allow_empty)
    " Either the range argument is empty or a list of two items where none is
    " zero and where the second item is larger or equal to the first.
    if a:allow_empty && empty(a:range)
        return 1
    endif
    if len(a:range) != 2
        throw "Invalid range of length: " . len(a:range)
    endif
    let l:start = a:range[0]
    let l:end = a:range[1]
    if l:start == 0 || l:end == 0 || l:start > l:end
        throw "Invalid range with zeroes: " . string(a:range)
    else
        return 1
    endif
endfun

fun! s:GetConflictInfo_FixEmptyRange(range)
    " If the range of the format [start, end] is invalid, return an empty
    " list.  Currently, just allow the special case that can result from
    " obtaining conflict ranges where end is one less than start if there is no
    " content.
    let l:start = a:range[0]
    let l:end = a:range[1]
    if l:end >= l:start
        return a:range
    elseif l:end == (l:start - 1)
        return []
    else
        throw "GetConflictInfo: Cannot flip invalid range: " . string(a:range)
    endif
endfun

fun! s:GetConflictInfo_AddAdditionalLineNumbers(info)
    " Add the line numbers of the separator and the base.  The latter will be
    " zero if there is no base content included in the conflict.
    call cursor(a:info.linenumber_start, 0)
    let a:info.linenumber_base = search(
                \ '^' . s:CONFLICT_MARKER_BASE . '\( .*\|$\)', 'nW')
    let a:info.linenumber_separator = search(
                \ '^' . s:CONFLICT_MARKER_SEPARATOR . '\( .*\|$\)', 'nW')
    if a:info.linenumber_separator == 0
        throw "GetConflictInfo: No conflict separator found in range: "
                    \ . string([a:info.linenumber_start,
                            \ a:info.linenumber_end])
    endif
endfun

fun! s:GetConflictInfo_AddRanges(info)
    " Add the ranges for the three sections.  linenumber_base determines if
    " there is a base section present.
    if a:info.linenumber_base
        let a:info.range_base = s:GetConflictInfo_FixEmptyRange(
                    \ [a:info.linenumber_base+1,
                            \ a:info.linenumber_separator-1])
        let a:info.range_ours = s:GetConflictInfo_FixEmptyRange(
                    \ [a:info.linenumber_start+1, a:info.linenumber_base-1])
    else
        let a:info.range_base = []
        let a:info.range_ours = s:GetConflictInfo_FixEmptyRange(
                    \ [a:info.linenumber_start+1,
                            \ a:info.linenumber_separator-1])
    endif
    let a:info.range_theirs = s:GetConflictInfo_FixEmptyRange(
                \ [a:info.linenumber_separator+1, a:info.linenumber_end-1])

    call s:EnforceValidContentRange(a:info.range_base, 1)
    call s:EnforceValidContentRange(a:info.range_ours, 1)
    call s:EnforceValidContentRange(a:info.range_theirs, 1)
endfun

fun! s:GetConflictInfo_AddContent(info)
    " Add the content of the three ranges
    let a:info.content_base = empty(a:info.range_base) ? []
                \ : getline(a:info.range_base[0], a:info.range_base[1])
    let a:info.content_ours = empty(a:info.range_ours) ? []
                \ : getline(a:info.range_ours[0], a:info.range_ours[1])
    let a:info.content_theirs = empty(a:info.range_theirs) ? []
                \ : getline(a:info.range_theirs[0], a:info.range_theirs[1])
endfun

fun! s:GetConflictInfo_GetMarkerComment(linenumber, marker)
    " Extract the comment after a:marker in a:linenumber
    let l:matches = matchlist(getline(a:linenumber),
                \ '^' . a:marker . ' \?\(.*\)$')
    if empty(l:matches)
        throw "GetConflictInfo: Could not match the marker " . a:marker
                    \ . " at line " . a:linenumber
                    \ . " : " . getline(a:linenumber)
    endif
    return l:matches[1]
endfun

fun! s:GetConflictInfo_AddConflictMarkerComments(info)
    " Add the comments after the conflict markers (all four)
    let a:info.marker_comment_start = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_start, s:CONFLICT_MARKER_START)
    let a:info.marker_comment_end = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_end, s:CONFLICT_MARKER_END)
    let a:info.marker_comment_separator = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_separator, s:CONFLICT_MARKER_SEPARATOR)
    if a:info.linenumber_base
        let a:info.marker_comment_base = s:GetConflictInfo_GetMarkerComment(
                    \ a:info.linenumber_base, s:CONFLICT_MARKER_BASE)
    else
        let a:info.marker_comment_base = ''
    endif
endfun


" === Conflict Slides ===

let s:ConflictSlides = {}

fun! s:ConflictSlides.resetAllVariables() dict
    " Set all variable keys in ConflictSlides to their unlocked default value.
    let self.start_line = 0
    let self.end_line = 0

    let self.base_content = ''
    let self.our_content = ''
    let self.their_content = ''

    let self.has_base_section = 0

    let self.origin_comment_ours = ''
    let self.origin_comment_theirs = ''
    let self.origin_comment_base = ''
    let self.origin_comment_sep = ''

    let self.locked_file = ''
    let self.locked = 0
    let self.lock_time = 0
endfun

" Initialize all dictionary variables
call s:ConflictSlides.resetAllVariables()

fun! s:ConflictSlides.releaseLock() dict
    " Return to normal operations and loose every information about the
    " previous conflict.
    "
    " Call the user-defined callback g:conflict_slides_post_release_callback()
    " that can be used to undo changes applied in the corresponding lock
    " callback.
    if !self.locked
        return
    endif

    call self.resetAllVariables()

    set modifiable

    if exists("*g:conflict_slides_post_release_callback")
        call g:conflict_slides_post_release_callback()
    endif
endfun

fun! s:ConflictSlides.getCurrentLockInfo()
    " Return a string with infos about the currently held lock or an empty
    " string if no lock is currently held
    if self.locked
        return "file(" . self.locked_file
                    \ . ") line(" . self.start_line
                    \ . ") lock-time(" . strftime("%H:%M", self.lock_time)
                    \ . ")."
    else
        return ''
    endif
endfun

fun! s:ConflictSlides.lockToCurrentConflict() dict
    " Assemble info about the conflict the cursor is currently in.
    "
    " Make the file unmodifiable because changes could compromise what is
    " recognized as the range of lines that belong to the conflict.
    "
    " Call the user-defined callback g:conflict_slides_post_lock_callback()
    " that can be used to apply mappings or change colors in conflict-locked
    " mode.
    if self.locked
        throw "AlreadyLocked" . self.getCurrentLockInfo()
    endif
    let l:conflict_info = CS_GetCurrentConflictInfo()

    let self.start_line = l:conflict_info.linenumber_start
    let self.end_line = l:conflict_info.linenumber_end

    let self.our_content = l:conflict_info.content_ours
    let self.their_content = l:conflict_info.content_theirs
    let self.base_content = l:conflict_info.content_base

    let self.has_base_section = l:conflict_info.linenumber_base ? 1 : 0

    let self.origin_comment_ours = l:conflict_info.marker_comment_start
    let self.origin_comment_theirs = l:conflict_info.marker_comment_end
    let self.origin_comment_base = l:conflict_info.marker_comment_base
    let self.origin_comment_sep = l:conflict_info.marker_comment_separator

    " ---

    let self.locked_file = resolve(expand('%:p'))
    let self.locked = 1
    let self.lock_time = localtime()

    set nomodifiable

    if exists("*g:conflict_slides_post_lock_callback")
        call g:conflict_slides_post_lock_callback()
    endif
endfun

fun! s:ConflictSlides.isEmptyContentSlide() dict
    " Return 1 if the conflict range is currently empty
    if !self.locked || self.end_line >= self.start_line
        return 0
    else
        return 1
    endif
endfun

fun! s:ConflictSlides.isInLockedFile() dict
    " Return 1 if the current file is the one with a locked conflict.
    if !self.locked || self.locked_file != resolve(expand('%:p'))
        return 0
    else
        return 1
    endif
endfun

fun! s:ConflictSlides.isWithinLockedConflict() dict
    " Return 1 if the cursor is positions inside the locked conflict
    " range.
    if !self.isInLockedFile()
        return 0
    endif
    if line('.') == self.getCursorDefaultLineNumber()
        return 1
    elseif line('.') < self.start_line || line('.') > self.end_line
        return 0
    endif
    return 1
endfun

fun! s:ConflictSlides.getCursorDefaultLineNumber() dict
    " Return the Cursor line number where the cursor is positioned in
    " the default case.
    " This factors in empty content -- also at the start and end of a
    " file.  A buffer has always one line with the number 1.
    if !self.locked
        throw "CannotPositionCursor: not locked to any conflict"
    endif
    let l:cursor_line_number = self.start_line
    if self.isEmptyContentSlide() && l:cursor_line_number != 1
        let l:cursor_line_number -= 1
    endif
    return l:cursor_line_number
endfun

fun! s:ConflictSlides.positionCursorAtDefaultLocation() dict
    " Move the cursor to a position that is always considered to be
    " inside the conflict range.
    if !self.locked
        throw "CannotPositionCursor: not locked to any conflict"
    endif
    if !self.isInLockedFile()
        throw "CannotPositionCursor: Not in the right file("
                    \ . self.locked_file . ")"
    endif
    call cursor(self.getCursorDefaultLineNumber(), 0)
endfun

fun! s:ConflictSlides.enforceConflictConditions(location_flags) dict
    " Throw an exception if the requirements specified in a:location_flags are
    " not met.  Valid flags are:
    " l - a conflict is locked
    " f - the current file is the locked file
    " c - the cursor is inside the conflict range
    " E - the current conflict content is non-empty
    "
    " Exceptions are raised in the order given in the above list.
    let l:flag_list = s:StringToCharList(a:location_flags)
    call s:EnforceArgumentMembership(l:flag_list, ['l', 'f', 'c', 'E'])

    if s:IsIn('l', l:flag_list) && !self.locked
        throw "ConflictConditionsNotMet: s:ConflictSlides is not "
                    \ . "locked to a conflict."
    endif
    if s:IsIn('f', l:flag_list) && !self.isInLockedFile()
        throw "ConflictConditionsNotMet: Not in the right file("
                    \ . self.locked_file . ")"
    endif
    if s:IsIn('c', l:flag_list) && !self.isWithinLockedConflict()
        throw "ConflictConditionsNotMet: Not within conflict range"
    endif
    if s:IsIn('E', l:flag_list) && self.isEmptyContentSlide()
        throw "ConflictConditionsNotMet: No conflict content"
    endif
endfun

fun! s:ConflictSlides.getMarkerLine(marker, comment) dict
    " Return a:marker, appended by space and a:comment if a:comment is
    " not empty.
    if empty(a:comment)
        return a:marker
    else
        return a:marker . ' ' . a:comment
    endif
endfun

fun! s:ConflictSlides.getNewContent_Complex(want_reverse, force_no_base) dict
    " A delegate of getNewContent that covers the cases with conflict
    " markers.
    let l:top_content = self.our_content
    let l:top_origin = self.origin_comment_ours
    let l:bottom_content = self.their_content
    let l:bottom_origin = self.origin_comment_theirs
    if a:want_reverse
        let [l:top_content, l:bottom_content]
                    \ = [l:bottom_content, l:top_content]
        let [l:top_origin, l:bottom_origin]
                    \ = [l:bottom_origin, l:top_origin]
    endif

    let l:new_start_marker = self.getMarkerLine(
                \ s:CONFLICT_MARKER_START, l:top_origin)
    let l:new_end_marker = self.getMarkerLine(
                \ s:CONFLICT_MARKER_END, l:bottom_origin)
    let l:new_base_marker = self.getMarkerLine(
                \ s:CONFLICT_MARKER_BASE, self.origin_comment_base)
    let l:new_sep_marker = self.getMarkerLine(
                \ s:CONFLICT_MARKER_SEPARATOR, self.origin_comment_sep)

    let l:all_new_content = [l:new_start_marker] + l:top_content
    if self.has_base_section && !a:force_no_base
        call extend(l:all_new_content, [l:new_base_marker] + self.base_content)
    endif
    call extend(l:all_new_content, [l:new_sep_marker] + l:bottom_content
                \ + [l:new_end_marker])
    return l:all_new_content
endfun

fun! s:ConflictSlides.getNewContent_Simple(content_map, request) dict
    " A delegate of getNewContent that covers the cases without
    " conflict markers.
    let l:base_not_available_error_message = "BaseNotAvailable"

    let l:combination_list = split(a:request)

    if len(l:combination_list) == 0
        throw "InvalidContentRequest: empty request"
    elseif len(l:combination_list) == 1
        let l:single_request = l:combination_list[0]
        if l:single_request == s:__base_key && !self.has_base_section
            throw l:base_not_available_error_message
        endif
        try
            return a:content_map[l:single_request]
        catch /716/ " Key not present
            throw "Invalid content request: " . l:single_request
        endtry
    else
        let l:result_simple = []
        for l:content_part in l:combination_list
            if l:content_part == s:__base_key && !self.has_base_section
                throw l:base_not_available_error_message
            endif
            try
                call extend(l:result_simple, a:content_map[l:content_part])
            catch /716/ " Key not present
                throw "Invalid combined content request with item: "
                            \ . l:content_part
            endtry
        endfor
        return l:result_simple
    endif
endfun

let s:__base_key = 'base'
fun! s:ConflictSlides.getNewContent(content_type) dict
    " Return a list of content lines according to the request in
    " a:content_type.
    " Possible requests are the strings seen here in this function and a
    " combination of simple_content keys separated by space.
    let l:simple_content = {
                \ s:__base_key : self.base_content,
                \ 'ours' : self.our_content,
                \ 'theirs' : self.their_content,
                \ }
    if a:content_type == 'forward'
        return self.getNewContent_Complex(0, 0)
    elseif a:content_type == 'reverse'
        return self.getNewContent_Complex(1, 0)
    elseif a:content_type == 'forward-nobase'
        return self.getNewContent_Complex(0, 1)
    elseif a:content_type == 'reverse-nobase'
        return self.getNewContent_Complex(1, 1)
    else
        return self.getNewContent_Simple(l:simple_content, a:content_type)
    endif
endfun

fun! s:ConflictSlides.modifyConflictContent(content_type, ...) dict
    " Change the content (the slide) currently displayed in the conflict
    " range.  See getNewContent for possible content_type values.
    "
    " If the additional argument 'append' is given the requested content will
    " be appended to the current content.  Otherwise the current content will
    " be replaced.
    "
    " If the additional argument 'jumpto' is given there won't be an error if
    " the cursor is currently not within the conflict range.  Note that it is
    " very easy to jump to the conflict with CS_MoveCursorToCurrentConflict().
    let l:location_requirement = 'lfc'
    let l:want_append = 0
    if a:0
        call s:EnforceArgumentMembership(a:000, ['append', 'jumpto'])
        if s:IsIn('append', a:000)
            let l:want_append = 1
        endif
        if s:IsIn('jumpto', a:000)
            let l:location_requirement = 'lf'
        endif
    endif
    call self.enforceConflictConditions(l:location_requirement)
    call self.positionCursorAtDefaultLocation()
    let l:new_content = self.getNewContent(a:content_type)
    set modifiable
    if !l:want_append && !self.isEmptyContentSlide()
        execute self.start_line . "," . self.end_line . "delete"
        let self.end_line = self.start_line - 1
    endif
    if !empty(l:new_content)
        call append(self.end_line, l:new_content)
        let self.end_line += len(l:new_content)
    endif
    call self.positionCursorAtDefaultLocation()
    set nomodifiable
endfun

" -----------------------------------------------------------------------------

" === Public Lock Functions ===

fun! CS_LockCurrentConflict(...)
    " Lock the current conflict delineated by conflict markers.  The optional
    " argument 'unlock-previous' will unlock the currently locked conflict.
    " Otherwise it is an error if a conflict is currently locked.
    let l:lock_info = s:ConflictSlides.getCurrentLockInfo()
    let l:want_unlock = 0
    if a:0
        call s:EnforceArgumentMembership(a:000, ['unlock-previous'])
        if s:IsIn('unlock-previous', a:000)
            let l:want_unlock = 1
        endif
    endif
    if s:ConflictSlides.locked && l:want_unlock
        call s:ConflictSlides.releaseLock()
    endif
    try
        call s:ConflictSlides.lockToCurrentConflict()
    catch /AlreadyLocked/
        call s:EchoImportant("Already locked to a conflict: " . l:lock_info
        return
    catch /NotInsideConflictMarkers/
        call s:EchoImportant("Cannot lock.  Not inside conflict markers.")
        return
    endtry
endfun

fun! CS_ReleaseLockedConflict()
    if !s:ConflictSlides.locked
        call s:EchoImportant("No conflict is locked")
    endif
    call s:ConflictSlides.releaseLock()
endfun

fun! CS_ModifyConflictContent(content_type, ...)
    " Change the content (the slide) currently displayed in the locked
    " conflict.  Possible content_type arguments are as follows:
    "
    " The content from the corresponding section of the conflict markers.
    " You can join multiple of these strings separated by space and they will
    " be inserted in order.  For example 'ours theirs'.
    "   'ours'
    "   'theirs'
    "   'base'
    "
    " Conflict content with markers.
    "   'forward' : the original conflict content before locking
    "   'forward-nobase' : the same as forward but suppress the base section
    "   'reverse' : like forward with the ours and theirs section exchanged.
    "   'reverse-nobase' : the same as reverse but suppress the base section
    "
    " ---
    "
    " The behavior can be influenced with the following optional arguments:
    "   'append' : append the new content to the current content
    "   'jumpto' : jump to the conflict first.  Otherwise it is an error if
    "           the cursor is not positioned inside the conflict range so that
    "           you can be sure to modify the conflict you are looking at.
    if !s:ConflictSlides.locked
        call s:EchoImportant("No conflict is locked")
        return
    endif
    try
        call call(s:ConflictSlides.modifyConflictContent,
                    \ [a:content_type] + a:000, s:ConflictSlides)
    catch /BaseNotAvailable/
        call s:EchoImportant("No base content available.  The conflict "
                    \ . "markers did not contain a base section.")
    catch /ConflictConditionsNotMet/
        call s:EchoImportant(v:exception)
    endtry
endfun

fun! CS_MoveCursorToCurrentConflict()
    " Move the cursor to the default location inside the currently locked
    " conflict.  It will be either the first line of the conflict range or one
    " line above it if the range is currently empty.
    try
        call s:ConflictSlides.positionCursorAtDefaultLocation()
    catch /CannotPositionCursor/
        call s:EchoImportant(v:exception)
    endtry
endfun

fun! CS_LockNextConflict(...)
    " Move to the next conflict and lock it.  If currently a conflict is
    " locked, unlock it first.  Influence the behavior with the following
    " optional arguments:
    "
    " 'restore-conflict' : restore the current conflict before unlocking it
    " 'backward' : reverse the search for the next conflict.
    let l:backward_request = ''
    let l:want_restore_current = 0
    if a:0
        call s:EnforceArgumentMembership(a:000,
                    \ ['restore-conflict', 'backward'])
        if s:IsIn('backward', a:000)
            let l:backward_request = 'backward'
        endif
        if s:IsIn('restore-conflict', a:000)
            let l:want_restore_current = 1
        endif
    endif
    if s:ConflictSlides.locked
        call s:ConflictSlides.positionCursorAtDefaultLocation()
        if l:want_restore_current
            call s:ConflictSlides.modifyConflictContent('forward')
        endif
        call s:ConflictSlides.releaseLock()
    endif
    if CS_MoveCursorToNextConflict(l:backward_request)
        call s:ConflictSlides.lockToCurrentConflict()
        return 1
    else
        return 0
    endif
endfun

fun! CS_SelectCurrentConflictRange(blink_ms)
    " Visually select the currently locked conflict range.  Select it
    " permanently by specifying a blink_ms time of zero.  Otherwise Vim sleeps
    " for the specified number of milliseconds and undoes the selection
    " afterwards.
    try
        call s:ConflictSlides.positionCursorAtDefaultLocation()
    catch /CannotPositionCursor/
        call s:EchoImportant(v:exception)
        return
    endtry
    if s:ConflictSlides.isEmptyContentSlide()
        return
    endif
    exe "normal! V" . s:ConflictSlides.end_line . "Go"
    if a:blink_ms
        redraw
        exe "sleep " . a:blink_ms . " m"
        exe "normal! V"
    endif
endfun

fun! CS_DisplayCurrentLockInfo()
    " Echo info about the currently locked conflict.
    if !s:ConflictSlides.locked
        call s:EchoImportant("No conflict is locked")
    else
        echo s:ConflictSlides.getCurrentLockInfo()
    endif
endfun

fun! CS_QueryState(state)
    " Return 1 if all the state flags given in a:state are true.  Valid flags
    " are the following chars:
    "   l - a conflict is locked
    "   f - the current file is the file with the locked conflict
    "   c - the cursor is inside the locked conflict range
    "   E - the current conflict content is non-empty
    try
        call s:ConflictSlides.enforceConflictConditions(a:state)
    catch /ConflictConditionsNotMet/
        return 0
    endtry
    return 1
endfun

" === Lock-Independent Public Functions ===

fun! CS_GetCurrentConflictInfo()
    " Return a dictionary with the following keys grouped in sections.
    "
    " conflict marker line numbers:
    "   linenumber_start
    "   linenumber_end
    "   linenumber_base
    "   linenumber_separator
    "
    " content ranges as lists of line numbers [start, end].  The list is empty
    " if there is no content:
    "   range_ours
    "   range_theirs
    "   range_base
    "
    " content lists of strings:
    "   content_ours
    "   content_theirs
    "   content_base
    "
    " The trailings strings after comment markers (empty if not present)
    "   marker_comment_start
    "   marker_comment_end
    "   marker_comment_base
    "   marker_comment_separator
    "
    " linenumber_base determines if there is a base section present.
    " (zero if not)
    "
    let l:save_cursor = getpos(".")
    let l:conflict_info = {}

    let l:range = s:GetCurrentConflictRange()
    if empty(l:range)
        throw "NotInsideConflictMarkers"
    endif
    let [
                \ l:conflict_info.linenumber_start,
                \ l:conflict_info.linenumber_end] = l:range

    call s:GetConflictInfo_AddAdditionalLineNumbers(l:conflict_info)
    call s:GetConflictInfo_AddRanges(l:conflict_info)
    call s:GetConflictInfo_AddContent(l:conflict_info)
    call s:GetConflictInfo_AddConflictMarkerComments(l:conflict_info)

    call setpos('.', l:save_cursor)
    return l:conflict_info
endfun

fun! CS_MoveCursorToNextConflict(...)
    " Move to the start of the next conflict.  If the optional argument is the
    " string 'backward', the start of the previous conflict will be searched
    " for.
    "
    " This works independently of any conflict-slide locks.  Just move to the
    " next conflict marker.
    let l:want_backward = 0
    if a:0
        call s:EnforceArgumentMembership(a:000, ['backward'])
        if s:IsIn('backward', a:000)
            let l:want_backward = 1
        endif
    endif
    let l:starting_line = line('.')
    let l:searchflags = 'sw' . (l:want_backward ? 'b' : '')
    let l:found_new_location = search(s:CONFLICT_MARKER_START, l:searchflags)
    if l:found_new_location
        let l:new_line = line('.')
        if (l:want_backward && l:new_line > l:starting_line)
                    \ || (!l:want_backward && l:new_line < l:starting_line)
            call s:EchoImportant("search wrapped around file borders")
        endif
        return 1
    else
        call s:EchoImportant("No conflict found")
        return 0
    endif
endfun
