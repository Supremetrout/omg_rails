require "rails_helper"
require "support/time_helpers"

RSpec.describe Ratings::UpdateService do
  let!(:player1) { create :player, name: "Player 1" }
  let(:elo1) { 1500 }
  let(:mu1) { 25 }
  let(:sigma1) { 8.33333 }
  let!(:player1_rating) { create :player_rating, player: player1, elo: elo1, mu: mu1, sigma: sigma1 }
  let!(:player2) { create :player, name: "Player 2" }
  let(:elo2) { 1500 }
  let(:mu2) { 25 }
  let(:sigma2) { 8.33333 }
  let!(:player2_rating) { create :player_rating, player: player2, elo: elo2, mu: mu2, sigma: sigma2 }

  let(:date_now) { DateTime.now.to_date }
  let(:size) { 1 }
  let!(:battle) { create :battle, size: size }

  describe "#update_player_ratings" do
    let(:winner) { Battle.winners[:allied] }

    subject { described_class.new(battle.id).update_player_ratings(winner) }

    before do
      travel_to Time.now
    end

    after do
      travel_back
    end

    context "with 1v1 battle" do
      before do
        create :battle_player, battle: battle, player: player1
        create :battle_player, :axis, battle: battle, player: player2
      end

      context "with equal starting rating" do
        context "with allied winner" do
          it "updates player ratings" do
            subject

            expect(player1_rating.reload.elo).to eq 2000
            expect(player1_rating.mu).to eq 29.39582964471032
            expect(player1_rating.sigma).to eq 7.171473132334705
            expect(player2_rating.reload.elo).to eq 1000
            expect(player2_rating.mu).to eq 20.604170355289675
            expect(player2_rating.sigma).to eq 7.171473132334705
          end

          it "updates player win loss" do
            subject

            expect(player1_rating.reload.wins).to eq 1
            expect(player1_rating.losses).to eq 0
            expect(player1_rating.last_played).to eq date_now
            expect(player2_rating.reload.wins).to eq 0
            expect(player2_rating.losses).to eq 1
            expect(player2_rating.last_played).to eq date_now
          end

          context "when there are bounding player ratings" do
            before do
              create :player_rating, mu: 40
              create :player_rating, mu: 10
            end

            it "updates player ratings" do
              subject

              expect(player1.player_rating.reload.elo).to eq 1646
              expect(player1_rating.mu).to eq 29.39582964471032
              expect(player1_rating.sigma).to eq 7.171473132334705
              expect(player2.player_rating.reload.elo).to eq 1353
              expect(player2_rating.mu).to eq 20.604170355289675
              expect(player2_rating.sigma).to eq 7.171473132334705
            end
          end
        end

        context "with axis winner" do
          let(:winner) { Battle.winners[:axis] }

          it "updates player ratings" do
            subject

            expect(player1_rating.reload.elo).to eq 1000
            expect(player1_rating.mu).to eq 20.604170355289675
            expect(player1_rating.sigma).to eq 7.171473132334705
            expect(player2_rating.reload.elo).to eq 2000
            expect(player2_rating.mu).to eq 29.39582964471032
            expect(player2_rating.sigma).to eq 7.171473132334705
          end

          it "updates player win loss" do
            subject

            expect(player1_rating.reload.wins).to eq 0
            expect(player1_rating.losses).to eq 1
            expect(player1_rating.last_played).to eq date_now
            expect(player2_rating.reload.wins).to eq 1
            expect(player2_rating.losses).to eq 0
            expect(player2_rating.last_played).to eq date_now
          end

          context "when there are bounding player ratings" do
            before do
              create :player_rating, mu: 40
              create :player_rating, mu: 10
            end

            it "updates player ratings" do
              subject

              expect(player1.player_rating.reload.elo).to eq 1353
              expect(player2.player_rating.reload.elo).to eq 1646
            end
          end
        end

        context "with pre-existing elo" do
          let(:elo1) { 1773 }
          let(:elo2) { 1773 }
          let(:mu1) { 27.234 }
          let(:mu2) { 27.234 }

          context "when sigma is large" do
            it "updates player ratings" do
              subject

              expect(player1.player_rating.reload.elo).to eq 2000
              expect(player1_rating.mu).to eq 31.629829644710316
              expect(player1_rating.sigma).to eq 7.171473132334705
              expect(player2.player_rating.reload.elo).to eq 1000
              expect(player2_rating.mu).to eq 22.83817035528968
              expect(player2_rating.sigma).to eq 7.171473132334705
            end
          end

          context "when sigma is small" do
            let(:sigma1) { 1.341234 }
            let(:sigma2) { 1.2345 }

            before do
              create :player_rating, mu: 40
              create :player_rating, mu: 10
            end

            it "updates player ratings", :aggregate_failures do
              subject

              expect(player1.player_rating.reload.elo).to eq 1583
              expect(player1_rating.mu).to eq 27.490374599177066
              expect(player1_rating.sigma).to eq 1.3225477969814246
              expect(player2.player_rating.reload.elo).to eq 1567
              expect(player2_rating.mu).to eq 27.016655205212224
              expect(player2_rating.sigma).to eq 1.2207250526942424
            end
          end
        end
      end

      context "with differing starting ratings" do
        let(:elo1) { 1773 }
        let(:mu1) { 27.234 }
        let(:sigma1) { 2.341234 }

        let(:elo2) { 1497 }
        let(:mu2) { 23.534 }
        let(:sigma2) { 2.2345 }

        before do
          create :player_rating, mu: 40
          create :player_rating, mu: 10
        end

        it "updates player ratings", :aggregate_failures do
          subject

          expect(player1.player_rating.reload.elo).to eq 1589
          expect(player1_rating.mu).to eq 27.675092801577037
          expect(player1_rating.sigma).to eq 2.266116905498489
          expect(player2.player_rating.reload.elo).to eq 1437
          expect(player2_rating.mu).to eq 23.132158495643026
          expect(player2_rating.sigma).to eq 2.169547101546173
        end
      end
    end

    context "with 4v4 battle" do
      let(:mu2) { 24.348 }
      let(:sigma2) { 4.1234 }
      let!(:player3) { create :player, name: "Player 3" }
      let(:mu3) { 29.23432 }
      let(:sigma3) { 3.33333 }
      let!(:player3_rating) { create :player_rating, player: player3, mu: mu3, sigma: sigma3 }
      let!(:player4) { create :player, name: "Player 4" }
      let(:mu4) { 16 }
      let(:sigma4) { 2.33333 }
      let!(:player4_rating) { create :player_rating, player: player4, mu: mu4, sigma: sigma4 }

      let!(:player5) { create :player, name: "Player 5" }
      let(:mu5) { 22 }
      let(:sigma5) { 1.33333 }
      let!(:player5_rating) { create :player_rating, player: player5, mu: mu5, sigma: sigma5 }
      let!(:player6) { create :player, name: "Player 6" }
      let(:mu6) { 31.2123 }
      let(:sigma6) { 2.7781 }
      let!(:player6_rating) { create :player_rating, player: player6, mu: mu6, sigma: sigma6 }
      let!(:player7) { create :player, name: "Player 7" }
      let(:mu7) { 13 }
      let(:sigma7) { 2.33333 }
      let!(:player7_rating) { create :player_rating, player: player7, mu: mu7, sigma: sigma7 }
      let!(:player8) { create :player, name: "Player 8" }
      let!(:player8_rating) { create :player_rating, player: player8 }

      before do
        create :battle_player, battle: battle, player: player1
        create :battle_player, battle: battle, player: player2
        create :battle_player, battle: battle, player: player3
        create :battle_player, battle: battle, player: player4
        create :battle_player, :axis, battle: battle, player: player5
        create :battle_player, :axis, battle: battle, player: player6
        create :battle_player, :axis, battle: battle, player: player7
        create :battle_player, :axis, battle: battle, player: player8
      end

      it "updates player ratings", :aggregate_failures do
        subject

        expect(player1_rating.reload.elo).to eq 1824
        expect(player1_rating.mu).to eq 27.720379996741908
        expect(player1_rating.sigma).to eq 7.780003165756892
        expect(player2_rating.reload.elo).to eq 1674
        expect(player2_rating.mu).to eq 25.014250065149096
        expect(player2_rating.sigma).to eq 4.0588380631229715
        expect(player3_rating.reload.elo).to eq 1931
        expect(player3_rating.mu).to eq 29.669808766471508
        expect(player3_rating.sigma).to eq 3.299904265765882
        expect(player4_rating.reload.elo).to eq 1189
        expect(player4_rating.mu).to eq 16.213528038398113
        expect(player4_rating.sigma).to eq 2.323015176899392
        expect(player5_rating.reload.elo).to eq 1504
        expect(player5_rating.mu).to eq 21.93009351701506
        expect(player5_rating.sigma).to eq 1.3337245163179297
        expect(player6_rating.reload.elo).to eq 2000
        expect(player6_rating.mu).to eq 30.909723404097956
        expect(player6_rating.sigma).to eq 2.7594197486723324
        expect(player7_rating.reload.elo).to eq 1000
        expect(player7_rating.mu).to eq 12.786471961601887
        expect(player7_rating.sigma).to eq 2.323015176899392
        expect(player8_rating.reload.elo).to eq 1523
        expect(player8_rating.mu).to eq 22.279620003258092
        expect(player8_rating.sigma).to eq 7.780003165756892
      end

      context "when there are bounding player ratings" do
        before do
          create :player_rating, mu: 40
          create :player_rating, mu: 10
        end

        it "updates player ratings", :aggregate_failures do
          subject

          expect(player1_rating.reload.elo).to eq 1590
          expect(player1_rating.mu).to eq 27.720379996741908
          expect(player1_rating.sigma).to eq 7.780003165756892
          expect(player2_rating.reload.elo).to eq 1500
          expect(player2_rating.mu).to eq 25.014250065149096
          expect(player2_rating.sigma).to eq 4.0588380631229715
          expect(player3_rating.reload.elo).to eq 1655
          expect(player3_rating.mu).to eq 29.669808766471508
          expect(player3_rating.sigma).to eq 3.299904265765882
          expect(player4_rating.reload.elo).to eq 1207
          expect(player4_rating.mu).to eq 16.213528038398113
          expect(player4_rating.sigma).to eq 2.323015176899392
          expect(player5_rating.reload.elo).to eq 1397
          expect(player5_rating.mu).to eq 21.93009351701506
          expect(player5_rating.sigma).to eq 1.3337245163179297
          expect(player6_rating.reload.elo).to eq 1696
          expect(player6_rating.mu).to eq 30.909723404097956
          expect(player6_rating.sigma).to eq 2.7594197486723324
          expect(player7_rating.reload.elo).to eq 1092
          expect(player7_rating.mu).to eq 12.786471961601887
          expect(player7_rating.sigma).to eq 2.323015176899392
          expect(player8_rating.reload.elo).to eq 1409
          expect(player8_rating.mu).to eq 22.279620003258092
          expect(player8_rating.sigma).to eq 7.780003165756892
        end
      end
    end
  end
end
