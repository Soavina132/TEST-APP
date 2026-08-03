export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      achievements: {
        Row: {
          description: string
          icon: string
          key: string
          label: string
          sort_order: number
          xp_reward: number
        }
        Insert: {
          description: string
          icon?: string
          key: string
          label: string
          sort_order?: number
          xp_reward?: number
        }
        Update: {
          description?: string
          icon?: string
          key?: string
          label?: string
          sort_order?: number
          xp_reward?: number
        }
        Relationships: []
      }
      admin_broadcasts: {
        Row: {
          created_at: string
          deleted_at: string | null
          id: string
          message: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          message: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          message?: string
        }
        Relationships: []
      }
      admin_logs: {
        Row: {
          action: string
          admin_id: string
          created_at: string
          id: string
          new_value: Json | null
          old_value: Json | null
          target_user_id: string | null
        }
        Insert: {
          action: string
          admin_id: string
          created_at?: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          target_user_id?: string | null
        }
        Update: {
          action?: string
          admin_id?: string
          created_at?: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          target_user_id?: string | null
        }
        Relationships: []
      }
      admin_user_messages: {
        Row: {
          created_at: string
          from_admin: boolean
          id: string
          message: string
          read_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          from_admin: boolean
          id?: string
          message: string
          read_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          from_admin?: boolean
          id?: string
          message?: string
          read_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      app_settings: {
        Row: {
          admin_label: string
          admin_phone: string
          afk_enabled: boolean | null
          afk_t1_max: number
          afk_t2_max: number
          afk_threshold: number | null
          ai_assistant_context: string | null
          ai_assistant_enabled: boolean
          chat_global_enabled: boolean | null
          chat_room_enabled: boolean | null
          chess_global_timer_enabled: boolean
          chess_global_timer_minutes: number
          contact_email: string | null
          contact_facebook: string | null
          contact_phone: string | null
          contact_whatsapp: string | null
          daily_bonus_amount_ar: number
          daily_bonus_enabled: boolean
          daily_bonus_streak_bonus: boolean
          deposit_help_html: string | null
          download_url: string | null
          fanorona_global_timer_enabled: boolean
          fanorona_global_timer_minutes: number
          game_commission_pct: number
          game_invite_timeout_minutes: number
          games_disabled: Json
          id: number
          live_enabled: boolean | null
          max_spectators: number | null
          min_deposit: number
          min_withdraw: number
          password_reset_help_html: string | null
          pause_message: string | null
          paused: boolean
          privacy_html: string | null
          ready_timeout_seconds: number | null
          referral_pct: number
          signup_bonus: number
          signup_help_html: string | null
          terms_html: string | null
          terms_text: string | null
          turn_seconds: number | null
          tutorials: Json | null
          updated_at: string
          withdrawal_help_html: string | null
        }
        Insert: {
          admin_label?: string
          admin_phone?: string
          afk_enabled?: boolean | null
          afk_t1_max?: number
          afk_t2_max?: number
          afk_threshold?: number | null
          ai_assistant_context?: string | null
          ai_assistant_enabled?: boolean
          chat_global_enabled?: boolean | null
          chat_room_enabled?: boolean | null
          chess_global_timer_enabled?: boolean
          chess_global_timer_minutes?: number
          contact_email?: string | null
          contact_facebook?: string | null
          contact_phone?: string | null
          contact_whatsapp?: string | null
          daily_bonus_amount_ar?: number
          daily_bonus_enabled?: boolean
          daily_bonus_streak_bonus?: boolean
          deposit_help_html?: string | null
          download_url?: string | null
          fanorona_global_timer_enabled?: boolean
          fanorona_global_timer_minutes?: number
          game_commission_pct?: number
          game_invite_timeout_minutes?: number
          games_disabled?: Json
          id?: number
          live_enabled?: boolean | null
          max_spectators?: number | null
          min_deposit?: number
          min_withdraw?: number
          password_reset_help_html?: string | null
          pause_message?: string | null
          paused?: boolean
          privacy_html?: string | null
          ready_timeout_seconds?: number | null
          referral_pct?: number
          signup_bonus?: number
          signup_help_html?: string | null
          terms_html?: string | null
          terms_text?: string | null
          turn_seconds?: number | null
          tutorials?: Json | null
          updated_at?: string
          withdrawal_help_html?: string | null
        }
        Update: {
          admin_label?: string
          admin_phone?: string
          afk_enabled?: boolean | null
          afk_t1_max?: number
          afk_t2_max?: number
          afk_threshold?: number | null
          ai_assistant_context?: string | null
          ai_assistant_enabled?: boolean
          chat_global_enabled?: boolean | null
          chat_room_enabled?: boolean | null
          chess_global_timer_enabled?: boolean
          chess_global_timer_minutes?: number
          contact_email?: string | null
          contact_facebook?: string | null
          contact_phone?: string | null
          contact_whatsapp?: string | null
          daily_bonus_amount_ar?: number
          daily_bonus_enabled?: boolean
          daily_bonus_streak_bonus?: boolean
          deposit_help_html?: string | null
          download_url?: string | null
          fanorona_global_timer_enabled?: boolean
          fanorona_global_timer_minutes?: number
          game_commission_pct?: number
          game_invite_timeout_minutes?: number
          games_disabled?: Json
          id?: number
          live_enabled?: boolean | null
          max_spectators?: number | null
          min_deposit?: number
          min_withdraw?: number
          password_reset_help_html?: string | null
          pause_message?: string | null
          paused?: boolean
          privacy_html?: string | null
          ready_timeout_seconds?: number | null
          referral_pct?: number
          signup_bonus?: number
          signup_help_html?: string | null
          terms_html?: string | null
          terms_text?: string | null
          turn_seconds?: number | null
          tutorials?: Json | null
          updated_at?: string
          withdrawal_help_html?: string | null
        }
        Relationships: []
      }
      assistant_messages: {
        Row: {
          content: string
          created_at: string
          id: string
          role: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          role: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          role?: string
          user_id?: string
        }
        Relationships: []
      }
      bug_reports: {
        Row: {
          admin_note: string | null
          category: string
          created_at: string
          id: string
          message: string
          resolved_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          admin_note?: string | null
          category?: string
          created_at?: string
          id?: string
          message: string
          resolved_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          admin_note?: string | null
          category?: string
          created_at?: string
          id?: string
          message?: string
          resolved_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      chat_members: {
        Row: {
          joined_at: string
          room_id: string
          user_id: string
        }
        Insert: {
          joined_at?: string
          room_id: string
          user_id: string
        }
        Update: {
          joined_at?: string
          room_id?: string
          user_id?: string
        }
        Relationships: []
      }
      chat_messages: {
        Row: {
          attachment_type: string | null
          attachment_url: string | null
          body: string | null
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          pinned: boolean
          reply_to: string | null
          room_id: string
          user_id: string
        }
        Insert: {
          attachment_type?: string | null
          attachment_url?: string | null
          body?: string | null
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          pinned?: boolean
          reply_to?: string | null
          room_id: string
          user_id: string
        }
        Update: {
          attachment_type?: string | null
          attachment_url?: string | null
          body?: string | null
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          pinned?: boolean
          reply_to?: string | null
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_messages_reply_to_fkey"
            columns: ["reply_to"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_messages_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "chat_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_mutes: {
        Row: {
          banned: boolean
          created_at: string
          reason: string | null
          until: string | null
          user_id: string
        }
        Insert: {
          banned?: boolean
          created_at?: string
          reason?: string | null
          until?: string | null
          user_id: string
        }
        Update: {
          banned?: boolean
          created_at?: string
          reason?: string | null
          until?: string | null
          user_id?: string
        }
        Relationships: []
      }
      chat_presence: {
        Row: {
          current_game: string | null
          last_seen: string
          typing_room: string | null
          typing_until: string | null
          user_id: string
        }
        Insert: {
          current_game?: string | null
          last_seen?: string
          typing_room?: string | null
          typing_until?: string | null
          user_id: string
        }
        Update: {
          current_game?: string | null
          last_seen?: string
          typing_room?: string | null
          typing_until?: string | null
          user_id?: string
        }
        Relationships: []
      }
      chat_reactions: {
        Row: {
          created_at: string
          emoji: string
          id: string
          message_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji: string
          id?: string
          message_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string
          id?: string
          message_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_reactions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_rooms: {
        Row: {
          created_at: string
          created_by: string | null
          dm_user_a: string | null
          dm_user_b: string | null
          enabled: boolean
          game_id: string | null
          id: string
          image_url: string | null
          joinable: boolean
          name: string | null
          type: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          dm_user_a?: string | null
          dm_user_b?: string | null
          enabled?: boolean
          game_id?: string | null
          id?: string
          image_url?: string | null
          joinable?: boolean
          name?: string | null
          type: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          dm_user_a?: string | null
          dm_user_b?: string | null
          enabled?: boolean
          game_id?: string | null
          id?: string
          image_url?: string | null
          joinable?: boolean
          name?: string | null
          type?: string
        }
        Relationships: []
      }
      chess_games: {
        Row: {
          black_id: string | null
          commission_pct: number
          created_at: string
          draw: boolean
          draw_black_by: string | null
          draw_offered_by: string | null
          draw_pick_value: number | null
          draw_picker_id: string | null
          draw_result: number | null
          draw_result_color: string | null
          draw_revealed_at: string | null
          draw_spun_by: string | null
          draw_white_by: string | null
          fen: string
          finished_at: string | null
          game_deadline: string | null
          host_id: string
          id: string
          is_private: boolean
          last_move_at: string | null
          ply: number
          pot: number
          ready_black: boolean
          ready_white: boolean
          room_code: string | null
          stake: number
          started_at: string | null
          status: Database["public"]["Enums"]["game_status"]
          turn: string
          turn_deadline: string | null
          turn_skips: Json
          white_id: string | null
          winner_id: string | null
        }
        Insert: {
          black_id?: string | null
          commission_pct?: number
          created_at?: string
          draw?: boolean
          draw_black_by?: string | null
          draw_offered_by?: string | null
          draw_pick_value?: number | null
          draw_picker_id?: string | null
          draw_result?: number | null
          draw_result_color?: string | null
          draw_revealed_at?: string | null
          draw_spun_by?: string | null
          draw_white_by?: string | null
          fen?: string
          finished_at?: string | null
          game_deadline?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          last_move_at?: string | null
          ply?: number
          pot?: number
          ready_black?: boolean
          ready_white?: boolean
          room_code?: string | null
          stake: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          turn?: string
          turn_deadline?: string | null
          turn_skips?: Json
          white_id?: string | null
          winner_id?: string | null
        }
        Update: {
          black_id?: string | null
          commission_pct?: number
          created_at?: string
          draw?: boolean
          draw_black_by?: string | null
          draw_offered_by?: string | null
          draw_pick_value?: number | null
          draw_picker_id?: string | null
          draw_result?: number | null
          draw_result_color?: string | null
          draw_revealed_at?: string | null
          draw_spun_by?: string | null
          draw_white_by?: string | null
          fen?: string
          finished_at?: string | null
          game_deadline?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          last_move_at?: string | null
          ply?: number
          pot?: number
          ready_black?: boolean
          ready_white?: boolean
          room_code?: string | null
          stake?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          turn?: string
          turn_deadline?: string | null
          turn_skips?: Json
          white_id?: string | null
          winner_id?: string | null
        }
        Relationships: []
      }
      chess_moves: {
        Row: {
          by_user: string
          created_at: string
          fen_after: string
          game_id: string
          id: string
          ply: number
          san: string
          uci: string
        }
        Insert: {
          by_user: string
          created_at?: string
          fen_after: string
          game_id: string
          id?: string
          ply: number
          san: string
          uci: string
        }
        Update: {
          by_user?: string
          created_at?: string
          fen_after?: string
          game_id?: string
          id?: string
          ply?: number
          san?: string
          uci?: string
        }
        Relationships: [
          {
            foreignKeyName: "chess_moves_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "chess_games"
            referencedColumns: ["id"]
          },
        ]
      }
      deposits: {
        Row: {
          amount: number
          created_at: string
          id: string
          method: string
          processed_at: string | null
          reference: string
          status: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          method: string
          processed_at?: string | null
          reference: string
          status?: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          method?: string
          processed_at?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["tx_status"]
          user_id?: string
          user_phone?: string | null
        }
        Relationships: []
      }
      domino_games: {
        Row: {
          commission_pct: number
          created_at: string
          current_turn: number
          finished_at: string | null
          first_tile_rule: string
          host_id: string
          id: string
          is_private: boolean
          max_players: number
          mode: string
          pot: number
          room_code: string | null
          scores: Json
          stake: number
          started_at: string | null
          state: Json
          status: Database["public"]["Enums"]["game_status"]
          target_score: number
          turn_deadline: string | null
          turn_skips: Json
          winner_id: string | null
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          current_turn?: number
          finished_at?: string | null
          first_tile_rule?: string
          host_id: string
          id?: string
          is_private?: boolean
          max_players: number
          mode?: string
          pot?: number
          room_code?: string | null
          scores?: Json
          stake: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          target_score?: number
          turn_deadline?: string | null
          turn_skips?: Json
          winner_id?: string | null
        }
        Update: {
          commission_pct?: number
          created_at?: string
          current_turn?: number
          finished_at?: string | null
          first_tile_rule?: string
          host_id?: string
          id?: string
          is_private?: boolean
          max_players?: number
          mode?: string
          pot?: number
          room_code?: string | null
          scores?: Json
          stake?: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          target_score?: number
          turn_deadline?: string | null
          turn_skips?: Json
          winner_id?: string | null
        }
        Relationships: []
      }
      domino_participants: {
        Row: {
          display_name: string
          forfeited: boolean
          game_id: string
          id: string
          joined_at: string
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          display_name: string
          forfeited?: boolean
          game_id: string
          id?: string
          joined_at?: string
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          display_name?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          joined_at?: string
          ready?: boolean
          slot?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "domino_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "domino_games"
            referencedColumns: ["id"]
          },
        ]
      }
      fanorona_games: {
        Row: {
          cols: number
          commission_pct: number
          created_at: string
          current_turn: number
          draw_black_by: string | null
          draw_result_color: string | null
          draw_revealed_at: string | null
          draw_spun_by: string | null
          draw_white_by: string | null
          finished_at: string | null
          game_deadline: string | null
          host_id: string
          id: string
          is_private: boolean
          mandatory_capture: boolean
          pot: number
          room_code: string | null
          rows: number
          stake: number
          started_at: string | null
          state: Json
          status: Database["public"]["Enums"]["game_status"]
          turn_deadline: string | null
          turn_skips: Json
          variant: string
          winner_id: string | null
        }
        Insert: {
          cols?: number
          commission_pct?: number
          created_at?: string
          current_turn?: number
          draw_black_by?: string | null
          draw_result_color?: string | null
          draw_revealed_at?: string | null
          draw_spun_by?: string | null
          draw_white_by?: string | null
          finished_at?: string | null
          game_deadline?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          mandatory_capture?: boolean
          pot?: number
          room_code?: string | null
          rows?: number
          stake: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          turn_deadline?: string | null
          turn_skips?: Json
          variant?: string
          winner_id?: string | null
        }
        Update: {
          cols?: number
          commission_pct?: number
          created_at?: string
          current_turn?: number
          draw_black_by?: string | null
          draw_result_color?: string | null
          draw_revealed_at?: string | null
          draw_spun_by?: string | null
          draw_white_by?: string | null
          finished_at?: string | null
          game_deadline?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          mandatory_capture?: boolean
          pot?: number
          room_code?: string | null
          rows?: number
          stake?: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          turn_deadline?: string | null
          turn_skips?: Json
          variant?: string
          winner_id?: string | null
        }
        Relationships: []
      }
      fanorona_participants: {
        Row: {
          color: string
          display_name: string
          forfeited: boolean
          game_id: string
          id: string
          joined_at: string
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          color: string
          display_name: string
          forfeited?: boolean
          game_id: string
          id?: string
          joined_at?: string
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          color?: string
          display_name?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          joined_at?: string
          ready?: boolean
          slot?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fanorona_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "fanorona_games"
            referencedColumns: ["id"]
          },
        ]
      }
      game_configs: {
        Row: {
          cover_url: string
          display_name: string
          instructions_dismissible: boolean
          max_online_capacity: number
          max_turn_skips: number
          rules_markdown: string
          slug: string
          turn_timer_seconds: number
          updated_at: string
        }
        Insert: {
          cover_url?: string
          display_name: string
          instructions_dismissible?: boolean
          max_online_capacity?: number
          max_turn_skips?: number
          rules_markdown?: string
          slug: string
          turn_timer_seconds?: number
          updated_at?: string
        }
        Update: {
          cover_url?: string
          display_name?: string
          instructions_dismissible?: boolean
          max_online_capacity?: number
          max_turn_skips?: number
          rules_markdown?: string
          slug?: string
          turn_timer_seconds?: number
          updated_at?: string
        }
        Relationships: []
      }
      game_spectators: {
        Row: {
          game_id: string
          id: string
          joined_at: string
          user_id: string
        }
        Insert: {
          game_id: string
          id?: string
          joined_at?: string
          user_id: string
        }
        Update: {
          game_id?: string
          id?: string
          joined_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ludo_games: {
        Row: {
          commission_pct: number
          created_at: string
          current_turn: number
          dice_override: Json | null
          disconnect_until: Json
          finished_at: string | null
          host_id: string
          id: string
          is_private: boolean
          max_players: number
          mode: string
          pot: number
          ready_deadline: string | null
          room_code: string | null
          spectator_chat_enabled: boolean | null
          stake: number
          started_at: string | null
          state: Json
          status: Database["public"]["Enums"]["game_status"]
          tournament_match_id: string | null
          winner_id: string | null
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          current_turn?: number
          dice_override?: Json | null
          disconnect_until?: Json
          finished_at?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          max_players: number
          mode?: string
          pot?: number
          ready_deadline?: string | null
          room_code?: string | null
          spectator_chat_enabled?: boolean | null
          stake: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          tournament_match_id?: string | null
          winner_id?: string | null
        }
        Update: {
          commission_pct?: number
          created_at?: string
          current_turn?: number
          dice_override?: Json | null
          disconnect_until?: Json
          finished_at?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          max_players?: number
          mode?: string
          pot?: number
          ready_deadline?: string | null
          room_code?: string | null
          spectator_chat_enabled?: boolean | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: Database["public"]["Enums"]["game_status"]
          tournament_match_id?: string | null
          winner_id?: string | null
        }
        Relationships: []
      }
      ludo_participants: {
        Row: {
          afk_t1: number | null
          afk_t2: number | null
          bot_intelligence: number
          bot_name: string | null
          bot_win_bias: number
          color: string
          consecutive_sixes: number
          display_name: string
          forfeited: boolean
          game_id: string
          id: string
          is_bot: boolean
          joined_at: string
          last_seen: string
          missed_turns: number
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          afk_t1?: number | null
          afk_t2?: number | null
          bot_intelligence?: number
          bot_name?: string | null
          bot_win_bias?: number
          color: string
          consecutive_sixes?: number
          display_name: string
          forfeited?: boolean
          game_id: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          last_seen?: string
          missed_turns?: number
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          afk_t1?: number | null
          afk_t2?: number | null
          bot_intelligence?: number
          bot_name?: string | null
          bot_win_bias?: number
          color?: string
          consecutive_sixes?: number
          display_name?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          last_seen?: string
          missed_turns?: number
          ready?: boolean
          slot?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ludo_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "ludo_games"
            referencedColumns: ["id"]
          },
        ]
      }
      money_offers: {
        Row: {
          active: boolean
          amount_ar: number | null
          created_at: string
          description: string | null
          id: string
          image_url: string | null
          sort_order: number
          title: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          amount_ar?: number | null
          created_at?: string
          description?: string | null
          id?: string
          image_url?: string | null
          sort_order?: number
          title: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          amount_ar?: number | null
          created_at?: string
          description?: string | null
          id?: string
          image_url?: string | null
          sort_order?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          id: string
          kind: string
          link: string | null
          read: boolean
          read_at: string | null
          ref_id: string | null
          title: string
          type: string | null
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          id?: string
          kind?: string
          link?: string | null
          read?: boolean
          read_at?: string | null
          ref_id?: string | null
          title: string
          type?: string | null
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          id?: string
          kind?: string
          link?: string | null
          read?: boolean
          read_at?: string | null
          ref_id?: string | null
          title?: string
          type?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      password_reset_requests: {
        Row: {
          admin_note: string | null
          code: string | null
          contact: string
          contact_type: string
          created_at: string
          id: string
          resolved_at: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          admin_note?: string | null
          code?: string | null
          contact: string
          contact_type: string
          created_at?: string
          id?: string
          resolved_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          admin_note?: string | null
          code?: string | null
          contact?: string
          contact_type?: string
          created_at?: string
          id?: string
          resolved_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      player_achievements: {
        Row: {
          achievement_key: string
          earned_at: string
          id: string
          user_id: string
        }
        Insert: {
          achievement_key: string
          earned_at?: string
          id?: string
          user_id: string
        }
        Update: {
          achievement_key?: string
          earned_at?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_achievements_achievement_key_fkey"
            columns: ["achievement_key"]
            isOneToOne: false
            referencedRelation: "achievements"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "player_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      poker_games: {
        Row: {
          commission_pct: number
          community_cards: number[]
          created_at: string
          created_by: string | null
          current_player: string | null
          finished_at: string | null
          hand_number: number
          id: string
          is_private: boolean
          max_players: number
          phase: string
          pot: number
          room_code: string | null
          stake: number
          started_at: string | null
          state: Json
          status: string
          turn_deadline: string | null
          updated_at: string
          winner_id: string | null
        }
        Insert: {
          commission_pct?: number
          community_cards?: number[]
          created_at?: string
          created_by?: string | null
          current_player?: string | null
          finished_at?: string | null
          hand_number?: number
          id?: string
          is_private?: boolean
          max_players?: number
          phase?: string
          pot?: number
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          turn_deadline?: string | null
          updated_at?: string
          winner_id?: string | null
        }
        Update: {
          commission_pct?: number
          community_cards?: number[]
          created_at?: string
          created_by?: string | null
          current_player?: string | null
          finished_at?: string | null
          hand_number?: number
          id?: string
          is_private?: boolean
          max_players?: number
          phase?: string
          pot?: number
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          turn_deadline?: string | null
          updated_at?: string
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "poker_games_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
          {
            foreignKeyName: "poker_games_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      poker_players: {
        Row: {
          bet_round: number
          chips: number
          game_id: string
          hand_result: Json | null
          hole_cards: number[]
          id: string
          is_ready: boolean
          joined_at: string
          last_action: string | null
          seat: number
          status: string
          total_bet: number
          user_id: string
        }
        Insert: {
          bet_round?: number
          chips?: number
          game_id: string
          hand_result?: Json | null
          hole_cards?: number[]
          id?: string
          is_ready?: boolean
          joined_at?: string
          last_action?: string | null
          seat: number
          status?: string
          total_bet?: number
          user_id: string
        }
        Update: {
          bet_round?: number
          chips?: number
          game_id?: string
          hand_result?: Json | null
          hole_cards?: number[]
          id?: string
          is_ready?: boolean
          joined_at?: string
          last_action?: string | null
          seat?: number
          status?: string
          total_bet?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "poker_players_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "poker_games"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          balance_ar: number
          banned: boolean
          created_at: string
          daily_streak: number
          email: string
          first_deposit_amount: number | null
          first_deposit_at: string | null
          first_game_at: string | null
          id: string
          is_banned: boolean
          is_premium: boolean
          last_daily_claim: string | null
          phone: string | null
          phone_number: string | null
          phone_verification_code: string | null
          phone_verification_code_hash: string | null
          phone_verification_requested_at: string | null
          phone_verified: boolean
          player_level: number
          pseudo: string
          referral_code: string
          referral_unlocked: boolean
          referred_by: string | null
          status: string
          suspended_until: string | null
          suspension_reason: string | null
          terms_accepted_at: string | null
          total_games: number
          total_wins: number
          unique_code: string | null
          warning_count: number
        }
        Insert: {
          avatar_url?: string | null
          balance_ar?: number
          banned?: boolean
          created_at?: string
          daily_streak?: number
          email: string
          first_deposit_amount?: number | null
          first_deposit_at?: string | null
          first_game_at?: string | null
          id: string
          is_banned?: boolean
          is_premium?: boolean
          last_daily_claim?: string | null
          phone?: string | null
          phone_number?: string | null
          phone_verification_code?: string | null
          phone_verification_code_hash?: string | null
          phone_verification_requested_at?: string | null
          phone_verified?: boolean
          player_level?: number
          pseudo: string
          referral_code: string
          referral_unlocked?: boolean
          referred_by?: string | null
          status?: string
          suspended_until?: string | null
          suspension_reason?: string | null
          terms_accepted_at?: string | null
          total_games?: number
          total_wins?: number
          unique_code?: string | null
          warning_count?: number
        }
        Update: {
          avatar_url?: string | null
          balance_ar?: number
          banned?: boolean
          created_at?: string
          daily_streak?: number
          email?: string
          first_deposit_amount?: number | null
          first_deposit_at?: string | null
          first_game_at?: string | null
          id?: string
          is_banned?: boolean
          is_premium?: boolean
          last_daily_claim?: string | null
          phone?: string | null
          phone_number?: string | null
          phone_verification_code?: string | null
          phone_verification_code_hash?: string | null
          phone_verification_requested_at?: string | null
          phone_verified?: boolean
          player_level?: number
          pseudo?: string
          referral_code?: string
          referral_unlocked?: boolean
          referred_by?: string | null
          status?: string
          suspended_until?: string | null
          suspension_reason?: string | null
          terms_accepted_at?: string | null
          total_games?: number
          total_wins?: number
          unique_code?: string | null
          warning_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "profiles_referred_by_fkey"
            columns: ["referred_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_referred_by_fkey"
            columns: ["referred_by"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_referred_by_fkey"
            columns: ["referred_by"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      rami_games: {
        Row: {
          commission_pct: number
          created_at: string
          created_by: string | null
          current_turn: number
          finished_at: string | null
          id: string
          is_private: boolean
          joker_mode: string
          max_players: number
          pot: number
          random_joker: number | null
          room_code: string | null
          stake: number
          started_at: string | null
          state: Json
          status: string
          turn_deadline: string | null
          turn_phase: string
          turn_skips: Json
          updated_at: string
          winner_id: string | null
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          created_by?: string | null
          current_turn?: number
          finished_at?: string | null
          id?: string
          is_private?: boolean
          joker_mode?: string
          max_players?: number
          pot?: number
          random_joker?: number | null
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          turn_deadline?: string | null
          turn_phase?: string
          turn_skips?: Json
          updated_at?: string
          winner_id?: string | null
        }
        Update: {
          commission_pct?: number
          created_at?: string
          created_by?: string | null
          current_turn?: number
          finished_at?: string | null
          id?: string
          is_private?: boolean
          joker_mode?: string
          max_players?: number
          pot?: number
          random_joker?: number | null
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          turn_deadline?: string | null
          turn_phase?: string
          turn_skips?: Json
          updated_at?: string
          winner_id?: string | null
        }
        Relationships: []
      }
      rami_participants: {
        Row: {
          display_name: string | null
          forfeited: boolean
          game_id: string
          hand_count: number
          id: string
          joined_at: string
          ready: boolean
          slot: number
          user_id: string
        }
        Insert: {
          display_name?: string | null
          forfeited?: boolean
          game_id: string
          hand_count?: number
          id?: string
          joined_at?: string
          ready?: boolean
          slot: number
          user_id: string
        }
        Update: {
          display_name?: string | null
          forfeited?: boolean
          game_id?: string
          hand_count?: number
          id?: string
          joined_at?: string
          ready?: boolean
          slot?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rami_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "rami_games"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_events: {
        Row: {
          created_at: string
          event_type: string
          id: string
          note: string | null
          referee_id: string
          referrer_id: string
          reward_amount: number
        }
        Insert: {
          created_at?: string
          event_type: string
          id?: string
          note?: string | null
          referee_id: string
          referrer_id: string
          reward_amount?: number
        }
        Update: {
          created_at?: string
          event_type?: string
          id?: string
          note?: string | null
          referee_id?: string
          referrer_id?: string
          reward_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "referral_events_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_events_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_events_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
          {
            foreignKeyName: "referral_events_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_events_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_events_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      referral_fraud_flags: {
        Row: {
          created_at: string
          details: Json | null
          id: string
          reason: string
          referee_id: string | null
          referrer_id: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        Insert: {
          created_at?: string
          details?: Json | null
          id?: string
          reason: string
          referee_id?: string | null
          referrer_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          details?: Json | null
          id?: string
          reason?: string
          referee_id?: string | null
          referrer_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_fraud_flags_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_referee_id_fkey"
            columns: ["referee_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_fraud_flags_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      referral_settings: {
        Row: {
          auto_flag_velocity: number
          campaign_bonus_pct: number | null
          campaign_expires_at: string | null
          campaign_label: string | null
          deposit_bonus_pct: number
          deposit_min_ar: number
          enabled: boolean
          id: number
          max_daily_new_referrals: number
          require_first_deposit: boolean
          require_phone_verification: boolean
          self_referral_block: boolean
          tier_diamond_min: number
          tier_diamond_mult: number
          tier_gold_min: number
          tier_gold_mult: number
          tier_silver_min: number
          tier_silver_mult: number
          updated_at: string
          win_commission_pct: number
        }
        Insert: {
          auto_flag_velocity?: number
          campaign_bonus_pct?: number | null
          campaign_expires_at?: string | null
          campaign_label?: string | null
          deposit_bonus_pct?: number
          deposit_min_ar?: number
          enabled?: boolean
          id?: number
          max_daily_new_referrals?: number
          require_first_deposit?: boolean
          require_phone_verification?: boolean
          self_referral_block?: boolean
          tier_diamond_min?: number
          tier_diamond_mult?: number
          tier_gold_min?: number
          tier_gold_mult?: number
          tier_silver_min?: number
          tier_silver_mult?: number
          updated_at?: string
          win_commission_pct?: number
        }
        Update: {
          auto_flag_velocity?: number
          campaign_bonus_pct?: number | null
          campaign_expires_at?: string | null
          campaign_label?: string | null
          deposit_bonus_pct?: number
          deposit_min_ar?: number
          enabled?: boolean
          id?: number
          max_daily_new_referrals?: number
          require_first_deposit?: boolean
          require_phone_verification?: boolean
          self_referral_block?: boolean
          tier_diamond_min?: number
          tier_diamond_mult?: number
          tier_gold_min?: number
          tier_gold_mult?: number
          tier_silver_min?: number
          tier_silver_mult?: number
          updated_at?: string
          win_commission_pct?: number
        }
        Relationships: []
      }
      support_messages: {
        Row: {
          created_at: string
          id: string
          message: string
          reply: string | null
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          message: string
          reply?: string | null
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          reply?: string | null
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      tournament_matches: {
        Row: {
          created_at: string
          finished_at: string | null
          game_id: string | null
          id: string
          match_index: number
          player_ids: string[]
          round: number
          status: string
          tournament_id: string
          winner_id: string | null
        }
        Insert: {
          created_at?: string
          finished_at?: string | null
          game_id?: string | null
          id?: string
          match_index: number
          player_ids: string[]
          round: number
          status?: string
          tournament_id: string
          winner_id?: string | null
        }
        Update: {
          created_at?: string
          finished_at?: string | null
          game_id?: string | null
          id?: string
          match_index?: number
          player_ids?: string[]
          round?: number
          status?: string
          tournament_id?: string
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tournament_matches_tournament_id_fkey"
            columns: ["tournament_id"]
            isOneToOne: false
            referencedRelation: "tournaments"
            referencedColumns: ["id"]
          },
        ]
      }
      tournament_registrations: {
        Row: {
          eliminated_round: number | null
          final_position: number | null
          id: string
          registered_at: string
          tournament_id: string
          user_id: string
        }
        Insert: {
          eliminated_round?: number | null
          final_position?: number | null
          id?: string
          registered_at?: string
          tournament_id: string
          user_id: string
        }
        Update: {
          eliminated_round?: number | null
          final_position?: number | null
          id?: string
          registered_at?: string
          tournament_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tournament_registrations_tournament_id_fkey"
            columns: ["tournament_id"]
            isOneToOne: false
            referencedRelation: "tournaments"
            referencedColumns: ["id"]
          },
        ]
      }
      tournaments: {
        Row: {
          bye_strategy: string
          commission_pct: number
          created_at: string
          created_by: string
          current_round: number
          description: string | null
          disconnect_grace_secs: number
          entry_fee_ar: number
          finished_at: string | null
          format: string
          game_slug: string
          id: string
          is_free: boolean
          join_timeout_secs: number
          match_duration_min: number
          max_players: number
          mode: string
          move_timer_secs: number
          name: string
          players_per_match: number
          prize_1_pct: number
          prize_2_pct: number
          prize_3_pct: number
          prize_pool: number
          registration_closes_at: string | null
          registration_opens_at: string | null
          require_phone_verification: boolean
          require_verified_account: boolean
          rewards_text: string | null
          runner_up_id: string | null
          season: number
          stake: number
          started_at: string | null
          starts_at: string | null
          status: string
          third_place_id: string | null
          top3: Json
          total_rounds: number
          winner_id: string | null
        }
        Insert: {
          bye_strategy?: string
          commission_pct?: number
          created_at?: string
          created_by: string
          current_round?: number
          description?: string | null
          disconnect_grace_secs?: number
          entry_fee_ar?: number
          finished_at?: string | null
          format?: string
          game_slug?: string
          id?: string
          is_free?: boolean
          join_timeout_secs?: number
          match_duration_min?: number
          max_players: number
          mode: string
          move_timer_secs?: number
          name: string
          players_per_match: number
          prize_1_pct?: number
          prize_2_pct?: number
          prize_3_pct?: number
          prize_pool?: number
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          require_phone_verification?: boolean
          require_verified_account?: boolean
          rewards_text?: string | null
          runner_up_id?: string | null
          season?: number
          stake?: number
          started_at?: string | null
          starts_at?: string | null
          status?: string
          third_place_id?: string | null
          top3?: Json
          total_rounds?: number
          winner_id?: string | null
        }
        Update: {
          bye_strategy?: string
          commission_pct?: number
          created_at?: string
          created_by?: string
          current_round?: number
          description?: string | null
          disconnect_grace_secs?: number
          entry_fee_ar?: number
          finished_at?: string | null
          format?: string
          game_slug?: string
          id?: string
          is_free?: boolean
          join_timeout_secs?: number
          match_duration_min?: number
          max_players?: number
          mode?: string
          move_timer_secs?: number
          name?: string
          players_per_match?: number
          prize_1_pct?: number
          prize_2_pct?: number
          prize_3_pct?: number
          prize_pool?: number
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          require_phone_verification?: boolean
          require_verified_account?: boolean
          rewards_text?: string | null
          runner_up_id?: string | null
          season?: number
          stake?: number
          started_at?: string | null
          starts_at?: string | null
          status?: string
          third_place_id?: string | null
          top3?: Json
          total_rounds?: number
          winner_id?: string | null
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount: number
          created_at: string
          id: string
          note: string | null
          ref_id: string | null
          type: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          note?: string | null
          ref_id?: string | null
          type: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          note?: string | null
          ref_id?: string | null
          type?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      withdrawals: {
        Row: {
          amount: number
          created_at: string
          id: string
          method: string
          processed_at: string | null
          status: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone: string
          recipient_name: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          method: string
          processed_at?: string | null
          status?: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone: string
          recipient_name?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          method?: string
          processed_at?: string | null
          status?: Database["public"]["Enums"]["tx_status"]
          user_id?: string
          user_phone?: string
          recipient_name?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      v_player_stats: {
        Row: {
          avatar_url: string | null
          daily_streak: number | null
          id: string | null
          player_level: number | null
          pseudo: string | null
          total_games: number | null
          total_wins: number | null
        }
        Insert: {
          avatar_url?: string | null
          daily_streak?: never
          id?: string | null
          player_level?: never
          pseudo?: string | null
          total_games?: never
          total_wins?: never
        }
        Update: {
          avatar_url?: string | null
          daily_streak?: never
          id?: string | null
          player_level?: never
          pseudo?: string | null
          total_games?: never
          total_wins?: never
        }
        Relationships: []
      }
      v_referral_stats: {
        Row: {
          active_referrals: number | null
          paid_events: number | null
          referral_code: string | null
          referrer_id: string | null
          tier: string | null
          total_earned_ar: number | null
          total_referrals: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      _admin_log: {
        Args: { _action: string; _new: Json; _old: Json; _target: string }
        Returns: undefined
      }
      _auto_advance_overdue_turns: { Args: never; Returns: undefined }
      _auto_cancel_open_games: { Args: never; Returns: undefined }
      _chess_payout: {
        Args: { _draw: boolean; _game_id: string; _winner: string }
        Returns: undefined
      }
      _domino_deal: { Args: { _n_players: number }; Returns: Json }
      _domino_end_round: {
        Args: { _game_id: string; _winner_slot: number }
        Returns: undefined
      }
      _domino_finalize: {
        Args: { _game_id: string; _winner_slot: number }
        Returns: undefined
      }
      _domino_hand_pips: { Args: { _hand: Json }; Returns: number }
      _domino_init_state: { Args: never; Returns: Json }
      _domino_lowest_pip_slot: {
        Args: { _game_id: string; _state: Json }
        Returns: number
      }
      _domino_next_playable_slot: {
        Args: { _from_slot: number; _game_id: string; _state: Json }
        Returns: number
      }
      _domino_next_round: { Args: { _game_id: string }; Returns: undefined }
      _domino_place_first: { Args: { _game_id: string }; Returns: undefined }
      _domino_required_starter_slot: {
        Args: { _game_id: string; _state: Json }
        Returns: number
      }
      _domino_slot_has_playable: {
        Args: { _slot: number; _state: Json }
        Returns: boolean
      }
      _domino_start: { Args: { _game_id: string }; Returns: undefined }
      _domino_visible: { Args: { _game_id: string }; Returns: boolean }
      _fanorona_axis: { Args: { _dc: number; _dr: number }; Returns: string }
      _fanorona_capture_lists:
        | {
            Args: { _board: Json; _from: number; _my: number; _to: number }
            Returns: Json
          }
        | {
            Args: {
              _board: Json
              _cols: number
              _from: number
              _my: number
              _rows: number
              _to: number
            }
            Returns: Json
          }
      _fanorona_finalize: {
        Args: { _game_id: string; _winner_slot: number }
        Returns: undefined
      }
      _fanorona_init_board:
        | { Args: never; Returns: Json }
        | { Args: { _cols: number; _rows: number }; Returns: Json }
      _fanorona_piece_can_capture:
        | {
            Args: {
              _board: Json
              _idx: number
              _last_axis: string
              _my: number
              _visited: Json
            }
            Returns: boolean
          }
        | {
            Args: {
              _board: Json
              _cols: number
              _idx: number
              _last_axis: string
              _my: number
              _rows: number
              _visited: Json
            }
            Returns: boolean
          }
      _fanorona_player_can_capture:
        | { Args: { _board: Json; _my: number }; Returns: boolean }
        | {
            Args: { _board: Json; _cols: number; _my: number; _rows: number }
            Returns: boolean
          }
      _fanorona_player_has_move:
        | { Args: { _board: Json; _my: number }; Returns: boolean }
        | {
            Args: { _board: Json; _cols: number; _my: number; _rows: number }
            Returns: boolean
          }
      _fanorona_visible: { Args: { _game_id: string }; Returns: boolean }
      _game_cfg: {
        Args: { _slug: string }
        Returns: {
          max_turn_skips: number
          turn_timer_seconds: number
        }[]
      }
      _game_visible: { Args: { _game_id: string }; Returns: boolean }
      _gen_room_code: { Args: never; Returns: string }
      _is_game_participant: {
        Args: { _game_id: string; _user_id: string }
        Returns: boolean
      }
      _ludo_active_humans: { Args: { _game_id: string }; Returns: number }
      _ludo_check_afk: {
        Args: { _game_id: string; _slot: number }
        Returns: undefined
      }
      _ludo_check_last_standing: { Args: { _game_id: string }; Returns: string }
      _ludo_ensure_state: { Args: { _game_id: string }; Returns: Json }
      _ludo_init_state: { Args: { _max_players: number }; Returns: Json }
      _ludo_is_safe: { Args: { _idx: number }; Returns: boolean }
      _ludo_next_slot: {
        Args: { _from: number; _game_id: string; _max: number }
        Returns: number
      }
      _ludo_start_for: {
        Args: { _game_id: string; _slot: number }
        Returns: number
      }
      _ludo_start_idx: { Args: { _slot: number }; Returns: number }
      _rami_check_win: {
        Args: { _state: Json; _uid: string }
        Returns: boolean
      }
      _rami_gen_code: { Args: never; Returns: string }
      _rami_is_joker: {
        Args: { _c: number; _mode: string; _rj: number }
        Returns: boolean
      }
      _rami_meld_type: {
        Args: { _cards: number[]; _mode: string; _rj: number }
        Returns: string
      }
      _rami_remove_one: {
        Args: { _arr: number[]; _v: number }
        Returns: number[]
      }
      _rami_validate_meld: { Args: { _cards: number[] }; Returns: boolean }
      _tournament_build_round: {
        Args: { _player_ids: string[]; _round: number; _tid: string }
        Returns: undefined
      }
      _try_unlock_referral: { Args: { _uid: string }; Returns: undefined }
      accept_terms: { Args: never; Returns: undefined }
      admin_add_bot:
        | { Args: { _bot_name: string; _game_id: string }; Returns: undefined }
        | {
            Args: {
              _bot_name: string
              _game_id: string
              _intelligence?: number
              _win_bias?: number
            }
            Returns: undefined
          }
      admin_adjust_balance: {
        Args: { _amount: number; _note: string; _user_id: string }
        Returns: undefined
      }
      admin_broadcast_delete: { Args: { _id: string }; Returns: undefined }
      admin_broadcast_send: { Args: { _message: string }; Returns: string }
      admin_chat_mute: {
        Args: {
          _ban: boolean
          _minutes: number
          _reason: string
          _user_id: string
        }
        Returns: undefined
      }
      admin_chat_unmute: { Args: { _user_id: string }; Returns: undefined }
      admin_create_community: {
        Args: { _image_url?: string; _name: string }
        Returns: string
      }
      admin_dashboard_totals: { Args: never; Returns: Json }
      admin_delete_community: { Args: { _room_id: string }; Returns: undefined }
      admin_delete_game: { Args: { _game_id: string }; Returns: undefined }
      admin_dm_send: {
        Args: { _message: string; _user_id: string }
        Returns: string
      }
      admin_force_finish_game: {
        Args: { _game_id: string; _winner_id?: string }
        Returns: undefined
      }
      admin_games_history: {
        Args: { _limit?: number }
        Returns: {
          commission_pct: number
          created_at: string
          duration_sec: number
          finished_at: string
          id: string
          max_players: number
          players: Json
          pot: number
          stake: number
          status: Database["public"]["Enums"]["game_status"]
          winner_pseudo: string
        }[]
      }
      admin_get_bot_config: {
        Args: { _participant_id: string }
        Returns: {
          intelligence: number
          win_bias: number
        }[]
      }
      admin_get_fraud_flags: {
        Args: { _status?: string }
        Returns: {
          created_at: string
          details: Json
          id: string
          reason: string
          referee_id: string
          referee_pseudo: string
          referrer_id: string
          referrer_pseudo: string
          status: string
        }[]
      }
      admin_join_game: {
        Args: { _display_name?: string; _game_id: string }
        Returns: undefined
      }
      admin_list_bug_reports: {
        Args: { _limit?: number; _status?: string }
        Returns: {
          admin_note: string
          category: string
          created_at: string
          id: string
          message: string
          pseudo: string
          resolved_at: string
          status: string
          user_id: string
        }[]
      }
      admin_list_games: { Args: never; Returns: Json }
      admin_list_phone_requests: {
        Args: never
        Returns: {
          code: string
          id: string
          phone: string
          pseudo: string
          requested_at: string
        }[]
      }
      admin_list_users: {
        Args: never
        Returns: {
          balance_ar: number
          created_at: string
          email: string
          id: string
          is_admin: boolean
          pseudo: string
        }[]
      }
      admin_list_users_sorted: {
        Args: { _sort: string }
        Returns: {
          balance_ar: number
          created_at: string
          email: string
          id: string
          is_admin: boolean
          phone_verified: boolean
          pseudo: string
        }[]
      }
      admin_permanently_delete_user: {
        Args: { _user_id: string }
        Returns: undefined
      }
      admin_process_deposit: {
        Args: { _approve: boolean; _id: string }
        Returns: undefined
      }
      admin_process_withdrawal: {
        Args: { _approve: boolean; _id: string }
        Returns: undefined
      }
      admin_refund_game: { Args: { _game_id: string }; Returns: undefined }
      admin_rename_bot: {
        Args: { _name: string; _participant_id: string }
        Returns: undefined
      }
      admin_reply_support: {
        Args: { _id: string; _reply: string }
        Returns: undefined
      }
      admin_reset_all_terms: { Args: never; Returns: number }
      admin_resolve_fraud_flag: {
        Args: { _flag_id: string; _pay_anyway?: boolean; _resolution: string }
        Returns: undefined
      }
      admin_search_users: {
        Args: { _q: string }
        Returns: {
          balance_ar: number
          banned: boolean
          created_at: string
          email: string
          id: string
          is_admin: boolean
          pseudo: string
          status: string
          unique_code: string
        }[]
      }
      admin_set_daily_bonus: {
        Args: { _amount_ar: number; _enabled: boolean; _streak_bonus?: boolean }
        Returns: undefined
      }
      admin_set_pause: {
        Args: { _message: string; _paused: boolean }
        Returns: undefined
      }
      admin_set_user_banned: {
        Args: { _banned: boolean; _user_id: string }
        Returns: undefined
      }
      admin_set_user_status: {
        Args: { _status: string; _user_id: string }
        Returns: undefined
      }
      admin_stats_daily: {
        Args: { _days: number }
        Returns: {
          day: string
          deposits: number
          wins: number
          withdrawals: number
        }[]
      }
      admin_update_bot: {
        Args: {
          _intelligence: number
          _participant_id: string
          _win_bias: number
        }
        Returns: undefined
      }
      admin_update_bug_report: {
        Args: { _admin_note?: string; _id: string; _status: string }
        Returns: undefined
      }
      admin_update_community: {
        Args: {
          _enabled: boolean
          _image_url: string
          _name: string
          _room_id: string
        }
        Returns: undefined
      }
      admin_update_referral_settings: {
        Args: {
          _auto_flag_velocity?: number
          _campaign_bonus_pct?: number
          _campaign_expires?: string
          _campaign_label?: string
          _deposit_bonus_pct?: number
          _deposit_min_ar?: number
          _enabled?: boolean
          _max_daily?: number
          _require_phone?: boolean
          _tier_diamond_min?: number
          _tier_diamond_mult?: number
          _tier_gold_min?: number
          _tier_gold_mult?: number
          _tier_silver_min?: number
          _tier_silver_mult?: number
          _win_commission_pct?: number
        }
        Returns: undefined
      }
      admin_update_settings: {
        Args: {
          _admin_label: string
          _admin_phone: string
          _game_commission_pct: number
          _min_deposit: number
          _min_withdraw: number
          _referral_pct: number
          _signup_bonus: number
        }
        Returns: undefined
      }
      admin_user_history: { Args: { _user_id: string }; Returns: Json }
      admin_verify_phone: {
        Args: { _approve: boolean; _user_id: string }
        Returns: undefined
      }
      chat_get_or_create_dm: { Args: { _other: string }; Returns: string }
      chat_get_or_create_game_room: {
        Args: { _game_id: string }
        Returns: string
      }
      chat_join_room: { Args: { _room_id: string }; Returns: undefined }
      chat_leave_room: { Args: { _room_id: string }; Returns: undefined }
      chat_pin: {
        Args: { _message_id: string; _pin: boolean }
        Returns: undefined
      }
      chat_presence_ping: { Args: { _game?: string }; Returns: undefined }
      chat_send: {
        Args: {
          _attachment_type?: string
          _attachment_url?: string
          _body: string
          _reply_to?: string
          _room_id: string
        }
        Returns: string
      }
      chat_typing: { Args: { _room_id: string }; Returns: undefined }
      check_and_award_achievements: {
        Args: { _uid: string }
        Returns: undefined
      }
      chess_accept_draw: { Args: { _game_id: string }; Returns: undefined }
      chess_auto_end: {
        Args: { _draw: boolean; _game_id: string; _winner: string }
        Returns: undefined
      }
      chess_check_global_timeout: {
        Args: { _game_id: string }
        Returns: undefined
      }
      chess_claim_win: {
        Args: { _draw: boolean; _game_id: string; _winner: string }
        Returns: undefined
      }
      chess_create: {
        Args: { _commission?: number; _private?: boolean; _stake: number }
        Returns: string
      }
      chess_decline_draw: { Args: { _game_id: string }; Returns: undefined }
      chess_draw_finalize: { Args: { _game_id: string }; Returns: undefined }
      chess_draw_pick: {
        Args: { _game_id: string; _value: number }
        Returns: undefined
      }
      chess_draw_pick_color: {
        Args: { _color: string; _game_id: string }
        Returns: undefined
      }
      chess_draw_spin: { Args: { _game_id: string }; Returns: undefined }
      chess_join_code: { Args: { _code: string }; Returns: string }
      chess_move: {
        Args: {
          _fen_after: string
          _game_id: string
          _san: string
          _uci: string
        }
        Returns: undefined
      }
      chess_offer_draw: { Args: { _game_id: string }; Returns: undefined }
      chess_request_or_accept_draw: {
        Args: { _game_id: string }
        Returns: undefined
      }
      chess_resign: { Args: { _game_id: string }; Returns: undefined }
      chess_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      chess_tick: { Args: { _game_id: string }; Returns: undefined }
      claim_daily_bonus: { Args: never; Returns: Json }
      cleanup_stale_open_games: { Args: never; Returns: number }
      create_game: {
        Args: { _max_players: number; _stake: number }
        Returns: string
      }
      create_private_game: {
        Args: { _max_players: number; _mode?: string; _stake: number }
        Returns: string
      }
      create_public_game: {
        Args: { _max_players: number; _stake: number }
        Returns: string
      }
      delete_my_account: { Args: never; Returns: undefined }
      domino_create:
        | {
            Args: {
              _commission?: number
              _max: number
              _mode?: string
              _private: boolean
              _stake: number
            }
            Returns: string
          }
        | {
            Args: {
              _commission?: number
              _max: number
              _mode?: string
              _private: boolean
              _stake: number
              _target_score?: number
            }
            Returns: string
          }
        | {
            Args: {
              _commission?: number
              _draw_mode?: string
              _max: number
              _mode?: string
              _private: boolean
              _stake: number
              _target_score?: number
            }
            Returns: string
          }
        | {
            Args: {
              _commission?: number
              _draw_mode?: string
              _first_tile_rule?: string
              _max: number
              _mode?: string
              _private: boolean
              _stake: number
              _target_score?: number
            }
            Returns: string
          }
      domino_forfeit: { Args: { _game_id: string }; Returns: undefined }
      domino_join: { Args: { _game_id: string }; Returns: undefined }
      domino_join_code: { Args: { _code: string }; Returns: string }
      domino_play: {
        Args: { _game_id: string; _move: Json }
        Returns: undefined
      }
      domino_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      domino_tick: { Args: { _game_id: string }; Returns: undefined }
      domino_tick_all: { Args: never; Returns: undefined }
      fanorona_check_global_timeout: {
        Args: { _game_id: string }
        Returns: undefined
      }
      fanorona_create:
        | {
            Args: { _commission?: number; _private: boolean; _stake: number }
            Returns: string
          }
        | {
            Args: {
              _commission?: number
              _mandatory_capture?: boolean
              _private: boolean
              _stake: number
              _variant?: string
            }
            Returns: string
          }
      fanorona_draw_finalize: { Args: { _game_id: string }; Returns: undefined }
      fanorona_draw_pick_color: {
        Args: { _color: string; _game_id: string }
        Returns: undefined
      }
      fanorona_draw_spin: { Args: { _game_id: string }; Returns: undefined }
      fanorona_forfeit: { Args: { _game_id: string }; Returns: undefined }
      fanorona_join: { Args: { _game_id: string }; Returns: undefined }
      fanorona_join_code: { Args: { _code: string }; Returns: string }
      fanorona_play: {
        Args: { _game_id: string; _move: Json }
        Returns: undefined
      }
      fanorona_request_or_accept_draw: {
        Args: { _game_id: string }
        Returns: undefined
      }
      fanorona_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      fanorona_tick: { Args: { _game_id: string }; Returns: undefined }
      find_or_create_game: {
        Args: { _max_players: number; _stake: number }
        Returns: string
      }
      finish_game: {
        Args: { _game_id: string; _winner_id: string }
        Returns: number
      }
      game_online_count: { Args: { _slug: string }; Returns: number }
      game_player_status: {
        Args: { _slug: string; _user_id: string }
        Returns: Json
      }
      gen_referral_code: { Args: never; Returns: string }
      gen_unique_code: { Args: never; Returns: string }
      get_ai_assistant_settings: {
        Args: never
        Returns: {
          context: string
          enabled: boolean
        }[]
      }
      get_daily_bonus_status: { Args: never; Returns: Json }
      get_email_by_phone: { Args: { _phone: string }; Returns: string }
      get_full_history: {
        Args: { _limit?: number; _uid: string }
        Returns: Json
      }
      get_legal_texts: {
        Args: never
        Returns: {
          privacy_html: string
          terms_html: string
        }[]
      }
      get_my_referrals: {
        Args: never
        Returns: {
          bonus_amount: number
          created_at: string
          id: string
          phone_verified: boolean
          pseudo: string
          referral_unlocked: boolean
        }[]
      }
      get_player_achievements: {
        Args: { _uid: string }
        Returns: {
          description: string
          earned_at: string
          icon: string
          key: string
          label: string
          xp_reward: number
        }[]
      }
      get_public_help_texts: {
        Args: never
        Returns: {
          reset_help: string
          signup_help: string
        }[]
      }
      get_public_profile: {
        Args: { _id: string }
        Returns: {
          avatar_url: string
          created_at: string
          daily_streak: number
          id: string
          player_level: number
          pseudo: string
          total_games: number
          total_wins: number
          unique_code: string
        }[]
      }
      get_public_profiles_min: {
        Args: { _ids: string[] }
        Returns: {
          avatar_url: string
          id: string
          pseudo: string
        }[]
      }
      get_referral_dashboard: { Args: never; Returns: Json }
      get_referral_leaderboard: {
        Args: { _limit?: number }
        Returns: {
          active_referrals: number
          avatar_url: string
          pseudo: string
          rank: number
          referrer_id: string
          tier: string
          total_earned_ar: number
        }[]
      }
      get_tournament_detail: { Args: { _tid: string }; Returns: Json }
      hall_of_fame: {
        Args: never
        Returns: {
          finished_at: string
          id: string
          mode: string
          name: string
          prize_pool: number
          season: number
          top3: Json
          winner_id: string
          winner_pseudo: string
        }[]
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_admin: { Args: never; Returns: boolean }
      is_game_disabled: { Args: { _slug: string }; Returns: boolean }
      join_game: { Args: { _game_id: string }; Returns: undefined }
      join_game_by_code: { Args: { _code: string }; Returns: string }
      leaderboard_winners: {
        Args: { _limit?: number; _period?: string }
        Returns: {
          avatar_url: string
          id: string
          name: string
          rank: number
          wins: number
        }[]
      }
      list_live_games: {
        Args: never
        Returns: {
          game_type: string
          id: string
          max_players: number
          mode: string
          players_count: number
          pot: number
          spectators_count: number
          stake: number
          started_at: string
        }[]
      }
      list_public_open_games: {
        Args: never
        Returns: {
          created_at: string
          id: string
          max_players: number
          players_count: number
          pot: number
          room_code: string
          stake: number
        }[]
      }
      list_tournaments:
        | {
            Args: { _status?: string }
            Returns: {
              created_at: string
              current_round: number
              finished_at: string
              id: string
              is_free: boolean
              max_players: number
              mode: string
              name: string
              prize_pool: number
              registered_count: number
              season: number
              stake: number
              status: string
              total_rounds: number
              winner_id: string
            }[]
          }
        | {
            Args: { _game_slug?: string; _limit?: number; _status?: string }
            Returns: {
              bye_strategy: string
              commission_pct: number
              created_at: string
              created_by: string
              current_round: number
              description: string | null
              disconnect_grace_secs: number
              entry_fee_ar: number
              finished_at: string | null
              format: string
              game_slug: string
              id: string
              is_free: boolean
              join_timeout_secs: number
              match_duration_min: number
              max_players: number
              mode: string
              move_timer_secs: number
              name: string
              players_per_match: number
              prize_1_pct: number
              prize_2_pct: number
              prize_3_pct: number
              prize_pool: number
              registration_closes_at: string | null
              registration_opens_at: string | null
              require_phone_verification: boolean
              require_verified_account: boolean
              rewards_text: string | null
              runner_up_id: string | null
              season: number
              stake: number
              started_at: string | null
              starts_at: string | null
              status: string
              third_place_id: string | null
              top3: Json
              total_rounds: number
              winner_id: string | null
            }[]
            SetofOptions: {
              from: "*"
              to: "tournaments"
              isOneToOne: false
              isSetofReturn: true
            }
          }
      ludo_bot_play: { Args: { _game_id: string }; Returns: Json }
      ludo_check_timeout: { Args: { _game_id: string }; Returns: Json }
      ludo_cleanup_empty_rooms: { Args: never; Returns: number }
      ludo_heartbeat: { Args: { _game_id: string }; Returns: undefined }
      ludo_move: {
        Args: { _game_id: string; _pawn_idx: number }
        Returns: Json
      }
      ludo_pass: { Args: { _game_id: string }; Returns: Json }
      ludo_purge_unready_rooms: { Args: never; Returns: number }
      ludo_quit: { Args: { _game_id: string }; Returns: undefined }
      ludo_roll: { Args: { _game_id: string }; Returns: Json }
      ludo_set_display_name: {
        Args: { _game_id: string; _name: string }
        Returns: undefined
      }
      ludo_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      ludo_tick_all: { Args: never; Returns: undefined }
      mark_messages_read: { Args: never; Returns: undefined }
      mark_notif_read: { Args: { _id?: string }; Returns: undefined }
      my_games: { Args: never; Returns: Json }
      my_ongoing_all: { Args: never; Returns: Json }
      participant_rename: {
        Args: { _game_id: string; _name: string }
        Returns: undefined
      }
      rami_create: {
        Args: {
          _commission: number
          _joker_mode?: string
          _max: number
          _private: boolean
          _stake: number
        }
        Returns: string
      }
      rami_discard: {
        Args: { _card: number; _game_id: string }
        Returns: undefined
      }
      rami_draw: {
        Args: { _from: string; _game_id: string }
        Returns: undefined
      }
      rami_forfeit: { Args: { _game_id: string }; Returns: undefined }
      rami_join_code: { Args: { _code: string }; Returns: string }
      rami_layoff: {
        Args: { _cards: number[]; _game_id: string; _meld_index: number }
        Returns: undefined
      }
      rami_meld: {
        Args: { _cards: number[]; _game_id: string }
        Returns: undefined
      }
      rami_request_refund: { Args: { _game_id: string }; Returns: undefined }
      rami_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      rami_start: { Args: { _game_id: string }; Returns: undefined }
      rami_tick: { Args: { _game_id: string }; Returns: undefined }
      request_password_reset: {
        Args: { _contact: string; _type: string }
        Returns: string
      }
      request_phone_verification: { Args: { _phone: string }; Returns: string }
      spectate_join: { Args: { _game_id: string }; Returns: undefined }
      spectate_leave: { Args: { _game_id: string }; Returns: undefined }
      submit_bug_report: {
        Args: { _category: string; _message: string }
        Returns: string
      }
      super_player_set_dice:
        | { Args: { _dice: number; _game_id: string }; Returns: undefined }
        | {
            Args: { _game_id: string; _slot: number; _value: number }
            Returns: undefined
          }
      tick_all_games: { Args: never; Returns: undefined }
      toggle_spectator_chat: {
        Args: { _enabled: boolean; _game_id: string }
        Returns: undefined
      }
      tournament_cancel: { Args: { _tid: string }; Returns: undefined }
      tournament_create: {
        Args: {
          _is_free: boolean
          _max_players: number
          _mode: string
          _name: string
          _season: number
          _stake: number
        }
        Returns: string
      }
      tournament_start: { Args: { _tid: string }; Returns: undefined }
      update_game_state: {
        Args: { _current_turn: number; _game_id: string; _state: Json }
        Returns: undefined
      }
      verify_phone_code: { Args: { _code: string }; Returns: boolean }
      weekly_top_winners: {
        Args: { _limit?: number }
        Returns: {
          avatar_url: string
          pseudo: string
          user_id: string
          wins: number
        }[]
      }
    }
    Enums: {
      app_role: "admin" | "user"
      game_status: "open" | "playing" | "finished" | "cancelled" | "drawing"
      tx_status: "pending" | "approved" | "rejected"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "user"],
      game_status: ["open", "playing", "finished", "cancelled", "drawing"],
      tx_status: ["pending", "approved", "rejected"],
    },
  },
} as const
