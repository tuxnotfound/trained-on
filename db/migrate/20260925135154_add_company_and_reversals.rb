class AddCompanyAndReversals < ActiveRecord::Migration[8.1]
  def change
    # The company behind the product, so a summary can say "OpenAI" rather than "ChatGPT's operator".
    add_column :vendors, :company, :string
    # A change that restores wording an earlier change removed, and removes what it added.
    add_reference :clause_events, :reverses_event, null: true, foreign_key: { to_table: :clause_events }
  end
end
