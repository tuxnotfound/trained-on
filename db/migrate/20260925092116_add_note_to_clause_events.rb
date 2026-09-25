class AddNoteToClauseEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :clause_events, :note, :text
  end
end
