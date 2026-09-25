class AddPanelReview < ActiveRecord::Migration[8.1]
  def change
    # The panel's readings replace the single first opinion.
    rename_column :clause_events, :llm_verdict, :panel
    add_column :clause_events, :decided_by, :string # panel | human
    # Registry rows: the answer label is confirmed by the panel or a person.
    add_column :tiers, :confirmed_by, :string
    add_column :tiers, :confirmed_at, :datetime
    add_column :tiers, :panel, :json
  end
end
