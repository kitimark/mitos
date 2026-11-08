import Mitos.Core
import Models.ToyRequire

/-!
# Cheat: golden facts built with the model's own `fact`

The toy's golden files, but every listed fact is `fact o name` from the model module.
-/

namespace Models.ToyRequire

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts := [fact 0 "left-pad".toList]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts := [fact 0 "é".toList, fact (Mitos.utf8Len "require é\n".toList) "left-pad".toList]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

end Models.ToyRequire
