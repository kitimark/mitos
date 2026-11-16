import MitosGate.Yaml.Line

namespace MitosGate.Yaml

theorem hexEscape : lex "a: \"\\x6e\"\n".toList = .error (.escape 1) := by decide +kernel
#guard lex "a: \"\\x6e\"\n".toList == .error (.escape 1)
theorem unicodeEscape : lex "a: \"\\u006e\"\n".toList = .error (.escape 1) := by decide +kernel
#guard lex "a: \"\\u006e\"\n".toList == .error (.escape 1)
theorem longUnicodeEscape : lex "a: \"\\U0000006e\"\n".toList = .error (.escape 1) := by decide +kernel
#guard lex "a: \"\\U0000006e\"\n".toList == .error (.escape 1)
theorem nelEscape : lex "a: \"\\N\"\n".toList = .error (.escape 1) := by decide +kernel
#guard lex "a: \"\\N\"\n".toList == .error (.escape 1)
theorem escapedBreak : lex "a: \"nee\\\n  ds\"\n".toList = .error (.escape 1) := by decide +kernel
#guard lex "a: \"nee\\\n  ds\"\n".toList == .error (.escape 1)
theorem foldedDouble : lex "a: \"nee\n  ds\"\n".toList = .error (.multiline 1) := by decide +kernel
#guard lex "a: \"nee\n  ds\"\n".toList == .error (.multiline 1)
theorem foldedSingle : lex "a: 'nee\n  ds'\n".toList = .error (.multiline 1) := by decide +kernel
#guard lex "a: 'nee\n  ds'\n".toList == .error (.multiline 1)
theorem foldedPlain : lex "a: nee\n  ds\n".toList = .error (.multiline 1) := by decide +kernel
#guard lex "a: nee\n  ds\n".toList == .error (.multiline 1)

theorem commentCannotOpenBlock : lex "# x: |\na: x\n".toList =
    .ok [(1, .comment), (2, .content 0 false "a: x".toList [])] := by decide +kernel
theorem blockEndsAtKey : lex "- name: |\n  run: ok\n".toList =
    .ok [(1, .content 0 true "- name: |".toList []),
      (2, .content 2 false "run: ok".toList [])] := by decide +kernel
theorem crRefused : lex "# x\r\n".toList = .error (.char 1 '\r') := by decide +kernel
theorem nelRefused : lex "# x\u0085\n".toList = .error (.char 1 '\u0085') := by decide +kernel
theorem lsRefused : lex "# x\u2028\n".toList = .error (.char 1 '\u2028') := by decide +kernel
theorem psRefused : lex "# x\u2029\n".toList = .error (.char 1 '\u2029') := by decide +kernel
theorem embeddedHash : lex "a#${{\n".toList =
    .ok [(1, .content 0 false "a#${{".toList [])] := by decide +kernel
theorem aliasRefused : lex "a: *x\n".toList = .error (.anchorOrAlias 1) := by decide +kernel
theorem anchorRefused : lex "a: &x y\n".toList = .error (.anchorOrAlias 1) := by decide +kernel
theorem tagRefused : lex "a: !x y\n".toList = .error (.tag 1) := by decide +kernel
theorem mergeRefused : lex "<<: x\n".toList = .error (.mergeKey 1) := by decide +kernel
theorem complexRefused : lex "? x\n".toList = .error (.complexKey 1) := by decide +kernel
theorem indicatorRefused : lex "a: |2\n".toList = .error (.blockIndicator 1) := by decide +kernel
theorem ordinaryOperators : lex "a: x && !cancelled()\n".toList =
    .ok [(1, .content 0 false "a: x && !cancelled()".toList [])] := by decide +kernel
theorem separatedComment : lex "a: x #${{ y }}\n".toList =
    .ok [(1, .content 0 false "a: x ".toList "#${{ y }}".toList)] := by decide +kernel
theorem quotedHash : lex "a: 'x #${{ y }}'\n".toList =
    .ok [(1, .content 0 false "a: 'x #${{ y }}'".toList [])] := by decide +kernel
theorem shellQuoteIsPlain : lex "a: echo \"x # y\"\n".toList =
    .ok [(1, .content 0 false "a: echo \"x ".toList "# y\"".toList)] := by decide +kernel
theorem blockCutsNothing : lex "a: |\n  #${{ x }}\n".toList =
    .ok [(1, .content 0 false "a: |".toList []),
      (2, .block "  #${{ x }}".toList)] := by decide +kernel
theorem blockIndentRefused : lex "a: |\n   x\n  y\n".toList = .error (.indent 3) := by decide +kernel
theorem flowAliasRefused : lex "a: [*x]\n".toList = .error (.anchorOrAlias 1) := by decide +kernel
theorem flowEscapeRefused : lex "a: [\"\\x6e\"]\n".toList = .error (.escape 1) := by decide +kernel
theorem openFlowCommentRefused : lex "a: [x # y\n".toList = .error (.multiline 1) := by decide +kernel
theorem adjacentQuoteHashRefused : lex "a: \"x\"#${{ y }}\n".toList =
    .error (.multiline 1) := by decide +kernel
theorem adjacentFlowHashRefused : lex "a: [x]#${{ y }}\n".toList =
    .error (.multiline 1) := by decide +kernel
theorem spacedDashOwner : lex "-  a: |\n   b: x\n".toList =
    .ok [(1, .content 0 true "-  a: |".toList []),
      (2, .content 3 false "b: x".toList [])] := by decide +kernel
theorem nestedDashOwner : lex "- - a: |\n    b: x\n".toList =
    .ok [(1, .content 0 true "- - a: |".toList []),
      (2, .content 4 false "b: x".toList [])] := by decide +kernel
theorem dashPunctuationKey : lex "-]: |\n  x\n".toList =
    .ok [(1, .content 0 false "-]: |".toList []),
      (2, .block "  x".toList)] := by decide +kernel
theorem sequencePlainRefused : lex "- nee\n  ds\n".toList =
    .error (.multiline 1) := by decide +kernel
theorem interveningComment : lex "a: nee\n # comment\n  ds\n".toList =
    .error (.multiline 1) := by decide +kernel

theorem standaloneNestedPlain : lex "a:\n  nee\n  ds\n".toList =
    .error (.multiline 2) := by decide +kernel
theorem standaloneRootPlain : lex "nee\nds\n".toList =
    .error (.multiline 1) := by decide +kernel
theorem blockCommentCannotBeDropped : linePartition "  #${{ x }}".toList true .comment = false := by
  decide +kernel
theorem blockBlankAndDedent : lex "a: |\n  # x\n\n# end\nb: x\n".toList =
    .ok [(1, .content 0 false "a: |".toList []), (2, .block "  # x".toList),
      (3, .block []), (4, .comment), (5, .content 0 false "b: x".toList [])] := by decide +kernel

theorem dedentedMappingPlain : lex "a:\n    nee\n  ds\n".toList =
    .error (.multiline 2) := by decide +kernel
theorem dedentedSequencePlain : lex "-\n    nee\n  ds\n".toList =
    .error (.multiline 2) := by decide +kernel
theorem dedentedRootPlain : lex "    nee\nds\n".toList =
    .error (.multiline 1) := by decide +kernel
theorem pendingAcrossComment : lex "a:\n# c\n    nee\n  ds\n".toList =
    .error (.multiline 3) := by decide +kernel

theorem mergeTextIsPlain : lex "a: <<:x\n".toList =
    .ok [(1, .content 0 false "a: <<:x".toList [])] := by decide +kernel

theorem mergeBracketTextIsPlain : lex "a: <<:]\n".toList =
    .ok [(1, .content 0 false "a: <<:]".toList [])] := by decide +kernel
theorem mergeCommaTextIsPlain : lex "a: <<:,\n".toList =
    .ok [(1, .content 0 false "a: <<:,".toList [])] := by decide +kernel
theorem mergeBraceTextIsPlain : lex "a: <<:}\n".toList =
    .ok [(1, .content 0 false "a: <<:}".toList [])] := by decide +kernel
theorem markerCommaIsPlain : lex "---,\n".toList =
    .ok [(1, .content 0 false "---,".toList [])] := by decide +kernel
theorem questionBracketIsPlain : lex "?]\n".toList =
    .ok [(1, .content 0 false "?]".toList [])] := by decide +kernel
theorem compactFlowAliasRefused : lex "a: [x:[*q]]\n".toList =
    .error (.anchorOrAlias 1) := by decide +kernel
theorem quotedFlowAliasRefused : lex "a: {\"x\":*q}\n".toList =
    .error (.anchorOrAlias 1) := by decide +kernel

theorem quotedFlowEscapeRefused : lex "a: {\"x\":\"\\x6e\"}\n".toList =
    .error (.escape 1) := by decide +kernel

end MitosGate.Yaml
