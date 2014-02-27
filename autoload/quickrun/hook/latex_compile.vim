let s:save_cpo = &cpo
set cpo&vim

function! s:delete_unused_lines(lines) "{{{
  let l:result = a:lines
  let l:index = 0
  while l:index < len(a:lines)
    if l:result[l:index] !~# '%\s*\(r\|R\)equire\s*$'
      let l:result[l:index] = ''
    endif
    let l:index += 1
  endwhile
  return l:result
endfunction "}}}

let s:latex_partial_markers = [
      \   ['^\s*\(\\\|% Fake\)subsubsection\>', 5],
      \   ['^\s*\(\\\|% Fake\)subsection\>',    4],
      \   ['^\s*\(\\\|% Fake\)section\>',       3],
      \   ['^\s*\(\\\|% Fake\)chapter\>',       2],
      \   ['^\s*\(\\\|% Fake\)part\>',          1],
      \ ]

if !exists('g:latexmk_partial_minimum_level')
  let g:latexmk_partial_minimum_level = 3
endif

function! s:get_target_region_start(lnum) "{{{
  let l:lnum = a:lnum
  while l:lnum > 0
    let l:line = getline(l:lnum)
    for [l:regex, l:level] in s:latex_partial_markers[(5 - g:latexmk_partial_minimum_level):]
      if l:line =~# l:regex
        return [l:lnum, l:level]
      endif
    endfor
    let l:lnum -= 1
  endwhile
  return [1, 0]
endfunction "}}}

function! s:get_target_region_end(level, lnum) "{{{
  let l:lnum = a:lnum
  while l:lnum <= line('$')
    let l:lnum += 1
    let l:line = getline(l:lnum)
    for [l:regex, l:level] in s:latex_partial_markers[(5-a:level):]
      if l:line =~# l:regex
        return l:lnum
      endif
    endfor
  endwhile
  return line('$')
endfunction "}}}

function! s:get_preamble_and_partial_tex(lnum) "{{{
  let l:lnum     = 0
  let l:preamble = []
  let l:result   = []
  let [l:start, l:level] = s:get_target_region_start(a:lnum)
  let l:end              = s:get_target_region_end(l:level, a:lnum)

  " Preamble Process {{{
  while l:lnum <= line('$')
    let l:lnum += 1
    let l:line = getline(l:lnum)
    if l:line =~# '^\s*\\begin\s*{\s*document\s*}'
      call add(l:result, l:line)
      break
    endif
    call add(l:preamble, l:line)
  endwhile " }}}

  " Document Process {{{
  while l:lnum <= line('$')
    let l:lnum += 1
    let l:line = getline(l:lnum)

    let l:line = substitute(l:line, '\\begin{\s*figure\s*}\(\[.*\]\)\?', '\\begin{figure}[h]', 'g')

    if l:line =~# '\s*\\end\s*{\s*document\s*}'
      call add(l:result, l:line)
      break
    elseif l:start <= l:lnum && l:lnum < l:end
      call add(l:result, l:line)
    else
      call add(l:result, '')
    endif
  endwhile "}}}

  " Preamble Modify {{{
  if l:level > 0
    let l:preamble_op = split(substitute(getline(l:start), '.*%\s*\(p\|P\)reamble\s*:\s*', '', ''), ',')
    let l:index = 0
    while l:index < len(l:preamble_op)
      let l:preamble_op[l:index] = substitute(substitute(l:preamble_op[l:index],'^\s\+','',''),'\s\+$','','')
      let l:index += 1
    endwhile

    let l:index = 0
    while l:index < len(l:preamble)
      if l:preamble[l:index] =~# '%\s*\(i\|I\)gnore\s*$'
        let l:preamble[l:index] = ''
      elseif l:preamble[l:index] =~# '%\s*\(o\|O\)ptional[^%,]*$'
        let l:tag = substitute(l:preamble[l:index], '.*%\s*\(o\|O\)ptional\s*:\s*', '', '')
        if index(l:preamble_op, l:tag) < 0
          let l:preamble[l:index] = ''
        endif
      elseif l:preamble[l:index] =~# '%\s*\(d\|D\)efault[^%,]*$'
        let l:tag = substitute(l:preamble[l:index], '.*%\s*\(d\|D\)efault\s*:\s*', '', '')
        if index(l:preamble_op, '!' . l:tag) >= 0
          let l:preamble[l:index] = ''
        endif
      endif
      let l:index += 1
    endwhile
  endif "}}}

  return extend(l:preamble, l:result)

endfunction "}}}

function! s:modify_filepath_in_log(file, orig, mod) "{{{
  let l:content = readfile(a:file)
  let l:index = 0
  while l:index < len(l:content)
    let l:content[l:index] = substitute(l:content[l:index], a:mod, a:orig, 'g')
    let l:index += 1
  endwhile
  call writefile(l:content, a:file)
endfunction
"}}}

let s:hook = {
      \ 'config': {
      \   'enable':  0,
      \   'partial_enable': 0,
      \   'partial_suffix': '_partial'
      \   }
      \ }

function! s:hook.on_module_loaded(session, context) "{{{
  if self.config.partial_enable
    let self.config.original     = a:session.config.srcfile
    let l:line = line('.')
    let a:session.config.srcfile = fnamemodify(a:session.config.srcfile, ':r') . self.config.partial_suffix . '.tex'
    let a:session.config.line    = l:line
    call writefile(s:get_preamble_and_partial_tex(l:line), a:session.config.srcfile)
  endif
endfunction "}}}

function! s:hook.on_success(session, context) "{{{
  if self.config.partial_enable
    if exists('g:latexmk_partial_previewer')
      let l:line = substitute(g:latexmk_partial_previewer, '%l', a:session.config.line, 'g')
      let l:file = substitute(l:line, '%f', fnamemodify(a:session.config.srcfile, ':r') . '.pdf', 'g')
      call system(l:file)
    endif
  endif
  echomsg 'Compile Success'
  cclose
endfunction "}}}

function! s:hook.on_failure(session, context) "{{{
  if self.config.partial_enable
    let l:logfile = fnamemodify(a:session.config.srcfile, ':r') . '.log'
    call s:modify_filepath_in_log(l:logfile, self.config.original, a:session.config.srcfile)
    cfile `=l:logfile`
  else
    cfile `=fnamemodify(a:session.config.srcfile, ':r') . '.log'`
  endif
  call system('latexmk -C ' . a:session.config.srcfile)
  copen
endfunction "}}}

function! quickrun#hook#latex_compile#new()
  return deepcopy(s:hook)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
