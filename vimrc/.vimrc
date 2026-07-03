set whichwrap+=<,>,[,]
set mouse=a
nnoremap <expr> <Down> line('.') == line('$') ? '$' : 'gj'
inoremap <expr> <Down> line('.') == line('$') ? '<C-o>$' : '<Down>'
