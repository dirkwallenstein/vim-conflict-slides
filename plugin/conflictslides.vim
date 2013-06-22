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


let g:CONFLICT_MARKER_START = '<<<<<<<'
let g:CONFLICT_MARKER_END = '>>>>>>>'
let g:CONFLICT_MARKER_BASE = '|||||||'
let g:CONFLICT_MARKER_SEPARATOR = '======='


fun! s:EchoImportant(message)
    " Try to echo important messages as described in the Vim docs.
    redraw | echohl WarningMsg | echomsg a:message | echohl None
endf

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
                \ '^' . g:CONFLICT_MARKER_BASE . '\( .*\|$\)', 'nW')
    let a:info.linenumber_separator = search(
                \ '^' . g:CONFLICT_MARKER_SEPARATOR . '\( .*\|$\)', 'nW')
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
                \ a:info.linenumber_start, g:CONFLICT_MARKER_START)
    let a:info.marker_comment_end = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_end, g:CONFLICT_MARKER_END)
    let a:info.marker_comment_base = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_base, g:CONFLICT_MARKER_BASE)
    let a:info.marker_comment_separator = s:GetConflictInfo_GetMarkerComment(
                \ a:info.linenumber_separator, g:CONFLICT_MARKER_SEPARATOR)
endfun


" === Conflict Slides ===

let g:ConflictSlides = {}

fun! g:ConflictSlides.releaseLock() dict
    let self.locked_file = ''
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
    let self.locked = 0
    let self.lock_time = 0

    set modifiable

    if exists("*g:conflict_slides_post_release_callback")
        call g:conflict_slides_post_release_callback()
    endif
endfun

" initialize
call g:ConflictSlides.releaseLock()

fun! g:ConflictSlides.lockToCurrentConflict() dict
    if self.locked
        throw "ConflictSlides: Already locked to a conflict "
                    \ . "in file(" . self.locked_file
                    \ . ") line(" . self.start_line
                    \ . ") at time(" . strftime("%H:%M", self.lock_time) . ")."
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

fun! g:ConflictSlides.isEmptyContentSlide() dict
    " Return 1 if the conflict range is currently empty
    if !self.locked || self.end_line >= self.start_line
        return 0
    else
        return 1
    endif
endfun

fun! g:ConflictSlides.isInLockedFile() dict
    " Return 1 if the current file is the one with a locked conflict.
    if !self.locked || self.locked_file != resolve(expand('%:p'))
        return 0
    else
        return 1
    endif
endfun

fun! g:ConflictSlides.isWithinLockedConflict() dict
    " Return 1 if the cursor is positions inside the locked conflict
    " range.
    try
        call self.enforceIsInActiveConflictRange()
    catch /NotInsideActiveConflict/
        return 0
    endtry
    return 1
endfun

fun! g:ConflictSlides.getCursorDefaultLineNumber() dict
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

fun! g:ConflictSlides.positionCursorAtDefaultLocation() dict
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

fun! g:ConflictSlides.enforceIsInActiveConflictRange() dict
    " Throw an exception if the cursor is not inside a locked conflict
    " range.
    if !self.locked
        throw "NotInsideActiveConflict: g:ConflictSlides is not "
                    \ . "locked to a conflict."
    endif
    if !self.isInLockedFile()
        throw "NotInsideActiveConflict: Not in the right file("
                    \ . self.locked_file . ")"
    endif
    if line('.') == self.getCursorDefaultLineNumber()
        return
    elseif line('.') < self.start_line || line('.') > self.end_line
        throw "NotInsideActiveConflict"
    endif
endfun

fun! g:ConflictSlides.getMarkerLine(marker, comment) dict
    " Return a:marker, appended by space and a:comment if a:comment is
    " not empty.
    if empty(a:comment)
        return a:marker
    else
        return a:marker . ' ' . a:comment
    endif
endfun

fun! g:ConflictSlides.getNewContent_Complex(want_reverse, force_no_base) dict
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
                \ g:CONFLICT_MARKER_START, l:top_origin)
    let l:new_end_marker = self.getMarkerLine(
                \ g:CONFLICT_MARKER_END, l:bottom_origin)
    let l:new_base_marker = self.getMarkerLine(
                \ g:CONFLICT_MARKER_BASE, self.origin_comment_base)
    let l:new_sep_marker = self.getMarkerLine(
                \ g:CONFLICT_MARKER_SEPARATOR, self.origin_comment_sep)

    let l:all_new_content = [l:new_start_marker] + l:top_content
    if self.has_base_section && !a:force_no_base
        call extend(l:all_new_content, [l:new_base_marker] + self.base_content)
    endif
    call extend(l:all_new_content, [l:new_sep_marker] + l:bottom_content
                \ + [l:new_end_marker])
    return l:all_new_content
endfun

fun! g:ConflictSlides.getNewContent_Simple(content_map, request) dict
    " A delegate of getNewContent that covers the cases without
    " conflict markers.
    let l:base_not_available_error_message = "InvalidContentRequest: "
                \ . "Base content not available through conflict markers"

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
fun! g:ConflictSlides.getNewContent(content_type) dict
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

fun! g:ConflictSlides.modifyConflictContent(content_type, want_append) dict
    " Change the content (the slide) currently displayed in the conflict
    " range.  See getNewContent for possible content_type values.  If
    " want_append is true the requested content will be appended to the
    " current content.  Otherwise the current content will be replaced.
    call self.enforceIsInActiveConflictRange()
    let l:new_content = self.getNewContent(a:content_type)
    set modifiable
    if !a:want_append && !self.isEmptyContentSlide()
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

" === Exported Functions ===

fun! CS_MoveCursorToCurrentConflict()
    try
        call g:ConflictSlides.positionCursorAtDefaultLocation()
    catch /CannotPositionCursor/
        call s:EchoImportant(v:exception)
    endtry
endfun

fun! CS_isInFileWithLockedConflict()
    return g:ConflictSlides.isInLockedFile()
endfun

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
        throw "GetConflictInfo: Not inside conflict markers"
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
