if exists("b:current_syntax")
  finish
endif

syntax keyword dhjsjsControl fn hui if uebok return while
syntax keyword dhjsjsType int string bool void
syntax keyword dhjsjsConstant true false null
syntax keyword dhjsjsUI activity compose viewmodel state

syntax match dhjsjsNumber "\<[0-9]\+\>"
syntax match dhjsjsIdentifier "\<[a-zA-Z_][a-zA-Z0-9_]*\>"

syntax region dhjsjsString start=+"+ skip=+\\"+ end=+"+
syntax match dhjsjsComment "//.*$"

highlight default link dhjsjsControl Keyword
highlight default link dhjsjsType Type
highlight default link dhjsjsConstant Constant
highlight default link dhjsjsUI Function
highlight default link dhjsjsNumber Number
highlight default link dhjsjsString String
highlight default link dhjsjsComment Comment

let b:current_syntax = "dhjsjs"
