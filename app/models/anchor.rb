# A stable phrase that identifies one paragraph of the training clause inside a
# document. The locator keeps a paragraph when it contains any anchor phrase
# (case-insensitive, after normalisation). Anchors are hand-chosen so that edits
# elsewhere in a long policy cannot move the clause, which is what the regex net
# of the go/no-go script got wrong.
class Anchor < ApplicationRecord
  belongs_to :document
  validates :phrase, presence: true
end
