class CreateHistoricalPlayerRatings < ActiveRecord::Migration[6.1]
  def change
    create_table :historical_player_ratings, comment: "" do |t|
      t.string :player_name, comment: "historical player name"
      t.references :player, index: true, null: true
      t.integer :elo, comment: "trueskill mu normalized between 1000 and 2000"
      t.float :mu, comment: "trueskill mu"
      t.float :sigma, comment: "trueskill sigma"
      t.date :last_played, comment: "last played match"

      t.timestamps
    end
  end
end