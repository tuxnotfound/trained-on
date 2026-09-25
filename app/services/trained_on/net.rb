module TrainedOn
  # The regex net from the go/no-go script. It no longer defines the clause; it
  # only proposes paragraphs a human might want to anchor, so a new training
  # paragraph cannot slip past silently.
  module Net
    CLAUSE = /
        \b(?:do|does|did|will|shall|may|might|can|could|would|won't|don't|doesn't|never|not)\s+(?:not\s+)?(?:be\s+)?(?:use[ds]?|using|train(?:s|ed|ing)?|utili[sz]e[ds]?)\b[^.;]{0,160}?\b(?:train|training|fine[- ]?tun|improv(?:e|ing)\s+(?:our|its|the|their)\s+(?:ai\s+)?(?:models?|technolog))
      | \b(?:use[ds]?|using|utili[sz]ed?)\s+(?:it\s+|them\s+|this\s+|that\s+)?(?:for|to)\s+(?:model\s+)?(?:train|fine[- ]?tun)
      | \b(?:used?|using)\s+(?:for|to)\s+(?:help\s+)?(?:develop|improve|enhance)[^.;]{0,60}?\btrain
      | \btrain(?:s|ed|ing)?\s+(?:and\s+improv(?:e|ing)\s+)?(?:our|its|their|the|any|new|more)?\s*(?:advanced\s+|ai\s+|machine[- ]learning\s+|artificial\s+intelligence\s+|large\s+language\s+|generative\s+)*(?:models?|ai\b|llms?|technolog)
      | \bopt[- ]?(?:in|out|ed)\b[^.;]{0,120}?\btrain
      | \btrain[^.;]{0,120}?\bopt[- ]?(?:in|out)\b
      | \bmodel\s+training\b
      | \btraining\s+(?:of\s+)?(?:our|its|their)\s+(?:ai\s+|large\s+language\s+)?models?
      | \btraining\s+purposes?\b
    /ix
    SUBJECT = /\b(?:your|you|customer|users?|inputs?|outputs?|prompts?|content|conversations?|materials?|submissions?|business\s+data|personal\s+data|customer\s+data|property|feedback|interactions?|publicly\s+available|public)\b/i
    EXCLUDE = [
      /\bsecurity\s+(?:awareness\s+)?training\b/i,
      /\bsecure\s+code\s+training\b/i,
      /\btraining\s+(?:materials?|curriculum|program(?:me)?s?)\b/i,
      /\btraining,\s+consulting\b/i,
      /\bprofessional\s+services\b/i,
      /\btraining\s+data\s+(?:may|could|might)\b/i,
      /\bcompet(?:e|ing|itive)\b/i,
      /\bmodel\s+(?:scraping|distillation|extraction)\b/i,
      /\brobots\.txt\b/i,
      /\bcrawl(?:ing|ers?)?\b/i
    ].freeze

    module_function

    def hit?(paragraph)
      paragraph.match?(CLAUSE) && paragraph.match?(SUBJECT) && EXCLUDE.none? { |re| paragraph.match?(re) }
    end
  end
end
