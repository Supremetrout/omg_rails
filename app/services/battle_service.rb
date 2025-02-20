class BattleService
  class BattleValidationError < StandardError; end

  # Cable message types
  CREATED_BATTLE = "created_battle".freeze
  PLAYER_JOINED = "player_joined".freeze
  PLAYER_JOINED_FULL = "player_joined_full".freeze
  PLAYER_READY = "player_ready".freeze
  PLAYER_UNREADY = "player_unready".freeze
  PLAYERS_ALL_READY = "players_all_ready".freeze
  BATTLEFILE_GENERATED = "battlefile_generated".freeze
  PLAYER_LEFT = "player_left".freeze
  REMOVE_BATTLE = "removed_battle".freeze
  BATTLE_FINALIZED = "battle_finalized".freeze
  PLAYER_ABANDONED = "player_abandoned".freeze
  PLAYERS_ALL_ABANDONED = "players_all_abandoned".freeze
  ELO_UPDATED = "elo_updated".freeze

  def initialize(player)
    @player = player
  end

  def create_battle(name, size, ruleset_id, initial_company_id)
    # Validate the player is not already in a non-final battle
    validate_player_can_create_or_join_battle

    # Validate the given company id matches a company belonging to the player and ruleset
    ruleset = validate_ruleset(ruleset_id)
    company = validate_company(initial_company_id, ruleset)
    # Validate player owns company
    validate_player_company(company)

    # Validate company has all valid platoons
    validate_company_platoons(company)

    # Validate player's company can ready
    validate_player_company_resources(company)

    ActiveRecord::Base.transaction do
      # Create new Battle for the ruleset, of name and size, and add the player's company to it
      battle = Battle.create!(name: name, size: size, ruleset: ruleset)
      BattlePlayer.create!(battle: battle, player: @player, company: company, side: company.side)

      # Broadcast
      message_hash = { type: CREATED_BATTLE, battle: battle.reload }
      # battle_message = Battle::Entity.represent(battle, type: :include_players)
      battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
      broadcast_cable(battle_message)
    end
  end

  def join_battle(battle_id, company_id)
    # Validate battle exists
    battle = validate_battle(battle_id)

    # Validate the player is not already in a non-final battle
    validate_player_can_create_or_join_battle

    battle.with_lock do
      # Validate battle is joinable
      validate_battle_joinable(battle)

      # Validate company exists and is of the same ruleset as the battle
      company = validate_company(company_id, battle.ruleset)
      # Validate player owns company
      validate_player_company(company)

      # Validate Battle has open slot on side of the company's faction
      validate_battle_has_open_spot(battle, company)

      # Validate company has all valid platoons
      validate_company_platoons(company)

      # Validate player's company can ready
      validate_player_company_resources(company)

      # Add company to battle
      ActiveRecord::Base.transaction do
        BattlePlayer.create!(battle: battle, player: @player, company: company, side: company.side)

        # If this causes the battle to be full, make that change
        if battle.reload.players_full?
          battle.full!
          type = PLAYER_JOINED_FULL
          Ratings::BalanceService.new(battle.id).find_most_balanced_teams
          BattleNotificationService.new(battle.id).notify_battle_full # TODO This could be async
        else
          type = PLAYER_JOINED
        end

        # Broadcast battle update
        message_hash = { type: type, battle: battle.reload }
        battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
        broadcast_cable(battle_message)
      end
      if battle.full?
        update_battle_elo(battle)
      end
    end
  end

  def ready_player(battle_id)
    # Validate battle exists
    battle = validate_battle(battle_id)

    type = nil
    battle.with_lock do
      # Validate battle is readyable
      validate_battle_readyable(battle)

      # Validate the player is in the battle
      validate_player_in_battle(battle)

      battle_player = BattlePlayer.includes(:company).find_by(battle: battle, player: @player)
      company = battle_player.company
      # Validate company has all valid platoons
      validate_company_platoons(company)
      # Validate player's company can ready
      validate_player_company_resources(company)

      battle_player.update!(ready: true)

      # If the battle has all players ready, move to generating state
      if battle.reload.all_players_ready?
        battle.ready!
        type = PLAYERS_ALL_READY
      else
        type = PLAYER_READY
      end

      # Broadcast battle update
      message_hash = { type: type, battle: battle }
      battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
      broadcast_cable(battle_message)
    end

    if type == PLAYERS_ALL_READY
      BattlefileGenerationJob.perform_async(battle_id)
    end
  end

  def unready_player(battle_id)
    # Validate battle exists
    battle = validate_battle(battle_id)

    battle.with_lock do
      # Validate battle is readyable
      validate_battle_readyable(battle)

      # Validate the player is in the battle
      validate_player_in_battle(battle)

      unless battle.reload.all_players_ready?
        BattlePlayer.find_by(battle: battle, player: @player).update!(ready: false)
      end

      battle.reload
      # Broadcast battle update
      message_hash = { type: PLAYER_UNREADY, battle: battle }
      battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
      broadcast_cable(battle_message)
    end
  end

  def leave_battle(battle_id)
    # Validate battle exists
    battle = validate_battle(battle_id)

    battle.with_lock do
      # Validate battle is leavable
      validate_battle_leavable(battle)

      # Validate the player is in the battle
      validate_player_in_battle(battle)

      # Attempt to remove player from battle
      BattlePlayer.find_by(battle: battle, player: @player).destroy

      if battle.full?
        battle.not_full!
        battle.save!
      end

      if battle.reload.battle_players.count == 0
        # Deleted the last player, delete the battle
        battle.destroy
        message_hash = { type: REMOVE_BATTLE, battle: battle }
      else
        unready_all_players(battle)
        message_hash = { type: PLAYER_LEFT, battle: battle.reload }
      end

      # Broadcast battle update
      battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
      broadcast_cable(battle_message)
    end
  end

  def finalize_battle(battle)
    validate_battle_final(battle)

    message_hash = { type: BATTLE_FINALIZED, battle: battle }

    battle_message = Entities::BattleMessage.represent message_hash
    broadcast_cable(battle_message)
  end

  def abandon_battle(battle_id)
    # Validate battle exists
    battle = validate_battle(battle_id)

    battle.with_lock do
      # Validate battle is abandonable
      validate_battle_abandonable(battle)

      # Validate the player is in the battle
      validate_player_in_battle(battle)

      # Set player abandon flag to true
      BattlePlayer.find_by(battle: battle, player: @player).update!(abandoned: true)

      # Are all players abandoned?
      if battle.reload.both_sides_abandoned?
        battle.abandoned! # Should this just destroy the battle? What's the value in keeping it
        type = PLAYERS_ALL_ABANDONED
      else
        type = PLAYER_ABANDONED
      end

      # Broadcast battle update
      message_hash = { type: type, battle: battle.reload }
      battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
      broadcast_cable(battle_message)
    end
  end

  def update_battle_elo(battle)
    axis_elo = 0
    allied_elo = 0
    battle.battle_players.each do |player|
      if player.side == "axis"
        axis_elo += player.player_elo
      else
        allied_elo += player.player_elo
      end
    end

    axis_elo = axis_elo / battle.size
    allied_elo = allied_elo / battle.size

    battle.elo_diff = axis_elo - allied_elo

    ActiveRecord::Base.transaction do
      battle.save!
    end

    message_hash = { type: ELO_UPDATED, battle: battle }
    # Broadcast battle update
    battle_message = Entities::BattleMessage.represent message_hash, type: :include_players
    broadcast_cable(battle_message)
  end

  private

  def broadcast_cable(message)
    ActionCable.server.broadcast BattlesChannel::CHANNEL, message
  end

  def validate_battle(battle_id)
    battle = Battle.includes(:battle_players).find(battle_id)
    raise BattleValidationError.new "Invalid battle #{battle_id}" unless battle.present?
    battle
  end

  def validate_battle_abandonable(battle)
    raise BattleValidationError.new "Cannot abandon battle in #{battle.state} state" unless battle.abandonable?
  end

  def validate_battle_leavable(battle)
    raise BattleValidationError.new "Cannot leave battle in #{battle.state} state" unless battle.leavable?
  end

  def validate_battle_joinable(battle)
    raise BattleValidationError.new "Cannot join battle in #{battle.state} state" unless battle.joinable?
  end

  def validate_battle_readyable(battle)
    raise BattleValidationError.new "Cannot ready up in a battle in #{battle.state} state" unless battle.full?
  end

  def validate_player_in_battle(battle)
    raise BattleValidationError.new "Player #{@player.name} is not in battle #{battle.id}" unless battle.battle_players.find_by(player: @player).present?
  end

  def validate_player_company_resources(company)
    unless company.resources_valid?
      error_string = ""
      if company.man.negative?
        error_string << "Man [#{company.man}] "
      end
      if company.mun.negative?
        error_string << "Mun [#{company.mun}] "
      end
      if company.fuel.negative?
        error_string << "Fuel [#{company.fuel}] "
      end
      raise BattleValidationError.new "Player #{@player.name}'s Company #{company.id} cannot have negative resources: #{error_string}"
    end
  end

  def validate_battle_final(battle)
    raise BattleValidationError.new "Cannot send finalize message for battle in non-final state #{battle.state}" unless battle.final?
  end

  def validate_ruleset(ruleset_id)
    ruleset = Ruleset.find(ruleset_id)
    raise BattleValidationError.new "Invalid Ruleset id #{ruleset_id}" unless ruleset.present?
    ruleset
  end

  # Validate the given company id matches a company belonging to the player and ruleset
  def validate_company(company_id, ruleset)
    company = ActiveCompany.find(company_id)
    raise BattleValidationError.new "Invalid Company id #{company_id}" unless company.present?
    raise BattleValidationError.new "Company #{company_id} has mismatched ruleset, expected #{ruleset.id} got #{company.ruleset.id}" unless company.ruleset == ruleset
    company
  end

  # Validate the player owns the company
  def validate_player_company(company)
    raise BattleValidationError.new "Player #{@player.id} does not own company #{company.id}" unless company.player == @player
  end

  # Validate the player is not already in a non-final battle
  def validate_player_can_create_or_join_battle
    unless BattlePlayer.in_active_battle.where(player: @player).count == 0
      raise BattleValidationError.new "Player #{@player.name} cannot create or join a battle while in an existing battle."
    end
  end

  # Validate Battle has open slot on side of the company's faction
  def validate_battle_has_open_spot(battle, company)
    unless BattlePlayer.where(battle: battle, side: company.side).count < battle.size
      raise BattleValidationError.new "Battle #{battle.id} has no available #{company.side} spots"
    end
  end

  def validate_company_platoons(company)
    categories_by_platoons = get_company_squads_by_platoon(company)

    raise BattleValidationError.new "Company cannot be empty" if categories_by_platoons.empty?

    categories_by_platoons.each do |category, category_platoons|
      # Category_platoons is a hash of category_position (platoon index) to an array of squads
      category_platoons.each do |position, squads|
        platoon_pop = squads.sum { |s| s.pop }
        unless platoon_pop == 0 || (CompanyService::MIN_POP_PER_PLATOON <= platoon_pop && platoon_pop <= CompanyService::MAX_POP_PER_PLATOON)
          raise BattleValidationError.new "Platoon at #{category} #{position} has invalid pop #{platoon_pop}"
        end
      end
    end
  end

  def get_company_squads_by_platoon(company)
    categories_hash = company.squads.group_by { |s| s[:tab_category] }
    categories_hash.transform_values { |category_squads| category_squads.group_by { |s| s[:category_position] } }
  end

  def unready_all_players(battle)
    return unless battle.reload.any_players_ready?

    BattlePlayer.where(battle: battle, ready: true).update_all(ready: false)
  end
end
