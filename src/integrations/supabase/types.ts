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
      admin_action_logs: {
        Row: {
          action: string
          admin_id: string
          created_at: string
          id: string
          payload: Json | null
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          action: string
          admin_id: string
          created_at?: string
          id?: string
          payload?: Json | null
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          action?: string
          admin_id?: string
          created_at?: string
          id?: string
          payload?: Json | null
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: []
      }
      admin_aliases: {
        Row: {
          admin_id: string
          avatar_url: string | null
          created_at: string
          id: string
          player_level: number
          pseudo: string
          total_games: number
          total_wins: number
        }
        Insert: {
          admin_id: string
          avatar_url?: string | null
          created_at?: string
          id?: string
          player_level?: number
          pseudo: string
          total_games?: number
          total_wins?: number
        }
        Update: {
          admin_id?: string
          avatar_url?: string | null
          created_at?: string
          id?: string
          player_level?: number
          pseudo?: string
          total_games?: number
          total_wins?: number
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
      admin_email_otps: {
        Row: {
          attempts: number
          code_hash: string
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          purpose: string
          user_id: string
        }
        Insert: {
          attempts?: number
          code_hash: string
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          purpose?: string
          user_id: string
        }
        Update: {
          attempts?: number
          code_hash?: string
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          purpose?: string
          user_id?: string
        }
        Relationships: []
      }
      admin_lockouts: {
        Row: {
          created_at: string
          fail_count: number
          locked_until: string
          reason: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          fail_count?: number
          locked_until: string
          reason?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          fail_count?: number
          locked_until?: string
          reason?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      admin_login_approvals: {
        Row: {
          approver_user_id: string | null
          created_at: string
          decided_at: string | null
          expires_at: string
          id: string
          override_reason: string | null
          requesting_ip: unknown
          requesting_user_agent: string | null
          requesting_user_id: string
          status: string
        }
        Insert: {
          approver_user_id?: string | null
          created_at?: string
          decided_at?: string | null
          expires_at?: string
          id?: string
          override_reason?: string | null
          requesting_ip?: unknown
          requesting_user_agent?: string | null
          requesting_user_id: string
          status?: string
        }
        Update: {
          approver_user_id?: string | null
          created_at?: string
          decided_at?: string | null
          expires_at?: string
          id?: string
          override_reason?: string | null
          requesting_ip?: unknown
          requesting_user_agent?: string | null
          requesting_user_id?: string
          status?: string
        }
        Relationships: []
      }
      admin_login_attempts: {
        Row: {
          created_at: string
          id: string
          identifier: string | null
          ip: unknown
          reason: string | null
          success: boolean
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          identifier?: string | null
          ip?: unknown
          reason?: string | null
          success: boolean
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          identifier?: string | null
          ip?: unknown
          reason?: string | null
          success?: boolean
          user_agent?: string | null
          user_id?: string | null
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
      admin_persona: {
        Row: {
          activated_at: string | null
          admin_id: string
          alias_id: string | null
          is_active: boolean
          persona_avatar: string | null
          persona_pseudo: string | null
          real_avatar_url: string | null
          real_player_level: number
          real_pseudo: string
          real_total_games: number
          real_total_wins: number
        }
        Insert: {
          activated_at?: string | null
          admin_id: string
          alias_id?: string | null
          is_active?: boolean
          persona_avatar?: string | null
          persona_pseudo?: string | null
          real_avatar_url?: string | null
          real_player_level?: number
          real_pseudo?: string
          real_total_games?: number
          real_total_wins?: number
        }
        Update: {
          activated_at?: string | null
          admin_id?: string
          alias_id?: string | null
          is_active?: boolean
          persona_avatar?: string | null
          persona_pseudo?: string | null
          real_avatar_url?: string | null
          real_player_level?: number
          real_pseudo?: string
          real_total_games?: number
          real_total_wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "admin_persona_alias_id_fkey"
            columns: ["alias_id"]
            isOneToOne: false
            referencedRelation: "admin_aliases"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_sessions: {
        Row: {
          approved_by: string | null
          created_at: string
          expires_at: string
          id: string
          ip: unknown
          last_seen_at: string
          mfa_verified: boolean
          override_reason: string | null
          revoke_reason: string | null
          revoked_at: string | null
          session_fingerprint: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          approved_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          ip?: unknown
          last_seen_at?: string
          mfa_verified?: boolean
          override_reason?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          session_fingerprint: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          approved_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          ip?: unknown
          last_seen_at?: string
          mfa_verified?: boolean
          override_reason?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          session_fingerprint?: string
          user_agent?: string | null
          user_id?: string
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
      announcements: {
        Row: {
          active: boolean
          body: string | null
          created_at: string
          id: string
          image_url: string | null
          link: string | null
          link_label: string | null
          title: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          body?: string | null
          created_at?: string
          id?: string
          image_url?: string | null
          link?: string | null
          link_label?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          body?: string | null
          created_at?: string
          id?: string
          image_url?: string | null
          link?: string | null
          link_label?: string | null
          title?: string
          updated_at?: string
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
          airtel_name: string
          airtel_phone: string
          billiard_commission_pct: number | null
          chat_global_enabled: boolean | null
          chat_room_enabled: boolean | null
          chess_commission_pct: number | null
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
          domino_commission_pct: number | null
          download_url: string | null
          fanorona_commission_pct: number | null
          fanorona_global_timer_enabled: boolean
          fanorona_global_timer_minutes: number
          faq_text: string
          game_commission_pct: number
          game_invite_timeout_minutes: number
          games_disabled: Json
          id: number
          legal_privacy: string | null
          legal_terms: string | null
          live_enabled: boolean | null
          ludo_commission_pct: number | null
          max_spectators: number | null
          max_stake: number
          min_deposit: number
          min_stake: number
          min_withdraw: number
          mvola_name: string
          mvola_phone: string
          orange_name: string
          orange_phone: string
          password_reset_help_html: string | null
          pause_message: string | null
          paused: boolean
          poker_commission_pct: number | null
          poker_min_players_start: number
          poker_rake_cap: number
          poker_rake_pct: number
          poker_starting_stack_ratio: number
          poker_tournament_late_reg_seconds: number
          poker_turn_seconds: number | null
          privacy_html: string | null
          privacy_text: string
          rami_commission_pct: number | null
          ready_timeout_seconds: number | null
          referral_enabled: boolean
          referral_pct: number
          signup_bonus: number
          signup_help_html: string | null
          solo_bot_enabled: boolean
          terms_html: string | null
          terms_text: string | null
          tourn_max_concurrent_chess: number
          tourn_max_concurrent_domino: number
          tourn_max_concurrent_ludo: number
          tourn_max_concurrent_petanque: number
          tournament_commission_pct: number | null
          turn_seconds: number | null
          tuto_url: string
          tutorials: Json | null
          update_url: string
          updated_at: string
          withdrawal_fee_pct: number
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
          airtel_name?: string
          airtel_phone?: string
          billiard_commission_pct?: number | null
          chat_global_enabled?: boolean | null
          chat_room_enabled?: boolean | null
          chess_commission_pct?: number | null
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
          domino_commission_pct?: number | null
          download_url?: string | null
          fanorona_commission_pct?: number | null
          fanorona_global_timer_enabled?: boolean
          fanorona_global_timer_minutes?: number
          faq_text?: string
          game_commission_pct?: number
          game_invite_timeout_minutes?: number
          games_disabled?: Json
          id?: number
          legal_privacy?: string | null
          legal_terms?: string | null
          live_enabled?: boolean | null
          ludo_commission_pct?: number | null
          max_spectators?: number | null
          max_stake?: number
          min_deposit?: number
          min_stake?: number
          min_withdraw?: number
          mvola_name?: string
          mvola_phone?: string
          orange_name?: string
          orange_phone?: string
          password_reset_help_html?: string | null
          pause_message?: string | null
          paused?: boolean
          poker_commission_pct?: number | null
          poker_min_players_start?: number
          poker_rake_cap?: number
          poker_rake_pct?: number
          poker_starting_stack_ratio?: number
          poker_tournament_late_reg_seconds?: number
          poker_turn_seconds?: number | null
          privacy_html?: string | null
          privacy_text?: string
          rami_commission_pct?: number | null
          ready_timeout_seconds?: number | null
          referral_enabled?: boolean
          referral_pct?: number
          signup_bonus?: number
          signup_help_html?: string | null
          solo_bot_enabled?: boolean
          terms_html?: string | null
          terms_text?: string | null
          tourn_max_concurrent_chess?: number
          tourn_max_concurrent_domino?: number
          tourn_max_concurrent_ludo?: number
          tourn_max_concurrent_petanque?: number
          tournament_commission_pct?: number | null
          turn_seconds?: number | null
          tuto_url?: string
          tutorials?: Json | null
          update_url?: string
          updated_at?: string
          withdrawal_fee_pct?: number
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
          airtel_name?: string
          airtel_phone?: string
          billiard_commission_pct?: number | null
          chat_global_enabled?: boolean | null
          chat_room_enabled?: boolean | null
          chess_commission_pct?: number | null
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
          domino_commission_pct?: number | null
          download_url?: string | null
          fanorona_commission_pct?: number | null
          fanorona_global_timer_enabled?: boolean
          fanorona_global_timer_minutes?: number
          faq_text?: string
          game_commission_pct?: number
          game_invite_timeout_minutes?: number
          games_disabled?: Json
          id?: number
          legal_privacy?: string | null
          legal_terms?: string | null
          live_enabled?: boolean | null
          ludo_commission_pct?: number | null
          max_spectators?: number | null
          max_stake?: number
          min_deposit?: number
          min_stake?: number
          min_withdraw?: number
          mvola_name?: string
          mvola_phone?: string
          orange_name?: string
          orange_phone?: string
          password_reset_help_html?: string | null
          pause_message?: string | null
          paused?: boolean
          poker_commission_pct?: number | null
          poker_min_players_start?: number
          poker_rake_cap?: number
          poker_rake_pct?: number
          poker_starting_stack_ratio?: number
          poker_tournament_late_reg_seconds?: number
          poker_turn_seconds?: number | null
          privacy_html?: string | null
          privacy_text?: string
          rami_commission_pct?: number | null
          ready_timeout_seconds?: number | null
          referral_enabled?: boolean
          referral_pct?: number
          signup_bonus?: number
          signup_help_html?: string | null
          solo_bot_enabled?: boolean
          terms_html?: string | null
          terms_text?: string | null
          tourn_max_concurrent_chess?: number
          tourn_max_concurrent_domino?: number
          tourn_max_concurrent_ludo?: number
          tourn_max_concurrent_petanque?: number
          tournament_commission_pct?: number | null
          turn_seconds?: number | null
          tuto_url?: string
          tutorials?: Json | null
          update_url?: string
          updated_at?: string
          withdrawal_fee_pct?: number
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
      balance_audit_log: {
        Row: {
          created_at: string
          db_user: string | null
          delta: number
          id: string
          new_balance: number
          old_balance: number
          txid: number | null
          user_id: string
        }
        Insert: {
          created_at?: string
          db_user?: string | null
          delta: number
          id?: string
          new_balance: number
          old_balance: number
          txid?: number | null
          user_id: string
        }
        Update: {
          created_at?: string
          db_user?: string | null
          delta?: number
          id?: string
          new_balance?: number
          old_balance?: number
          txid?: number | null
          user_id?: string
        }
        Relationships: []
      }
      billiard_games: {
        Row: {
          commission_pct: number
          created_at: string
          finished_at: string | null
          host_id: string
          id: string
          is_private: boolean
          max_players: number
          pot: number
          room_code: string | null
          stake: number
          started_at: string | null
          state: Json
          status: string
          winner_id: string | null
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          finished_at?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          max_players?: number
          pot?: number
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          winner_id?: string | null
        }
        Update: {
          commission_pct?: number
          created_at?: string
          finished_at?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          max_players?: number
          pot?: number
          room_code?: string | null
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          winner_id?: string | null
        }
        Relationships: []
      }
      billiard_participants: {
        Row: {
          ball_type: string | null
          created_at: string
          forfeited: boolean
          game_id: string
          id: string
          ready: boolean
          score: number
          slot: number
          user_id: string
        }
        Insert: {
          ball_type?: string | null
          created_at?: string
          forfeited?: boolean
          game_id: string
          id?: string
          ready?: boolean
          score?: number
          slot: number
          user_id: string
        }
        Update: {
          ball_type?: string | null
          created_at?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          ready?: boolean
          score?: number
          slot?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "billiard_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "billiard_games"
            referencedColumns: ["id"]
          },
        ]
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
          sender_avatar: string | null
          sender_name: string | null
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
          sender_avatar?: string | null
          sender_name?: string | null
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
          sender_avatar?: string | null
          sender_name?: string | null
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
          black_is_bot: boolean
          black_time_ms: number
          bot_intelligence: number | null
          bot_name: string | null
          commission_pct: number
          created_at: string
          draw: boolean
          draw_offered_by: string | null
          end_reason: string | null
          fen: string
          finished_at: string | null
          game_deadline: string | null
          host_id: string
          id: string
          is_private: boolean
          last_move_at: string | null
          mode: string
          paused: boolean
          ply: number
          pot: number
          resign_offered_by: string | null
          room_code: string | null
          stake: number
          started_at: string | null
          status: Database["public"]["Enums"]["game_status"]
          time_control_min: number
          turn: string
          turn_deadline: string | null
          white_id: string | null
          white_is_bot: boolean
          white_time_ms: number
          winner_id: string | null
        }
        Insert: {
          black_id?: string | null
          black_is_bot?: boolean
          black_time_ms?: number
          bot_intelligence?: number | null
          bot_name?: string | null
          commission_pct?: number
          created_at?: string
          draw?: boolean
          draw_offered_by?: string | null
          end_reason?: string | null
          fen?: string
          finished_at?: string | null
          game_deadline?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          last_move_at?: string | null
          mode?: string
          paused?: boolean
          ply?: number
          pot?: number
          resign_offered_by?: string | null
          room_code?: string | null
          stake: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          time_control_min?: number
          turn?: string
          turn_deadline?: string | null
          white_id?: string | null
          white_is_bot?: boolean
          white_time_ms?: number
          winner_id?: string | null
        }
        Update: {
          black_id?: string | null
          black_is_bot?: boolean
          black_time_ms?: number
          bot_intelligence?: number | null
          bot_name?: string | null
          commission_pct?: number
          created_at?: string
          draw?: boolean
          draw_offered_by?: string | null
          end_reason?: string | null
          fen?: string
          finished_at?: string | null
          game_deadline?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          last_move_at?: string | null
          mode?: string
          paused?: boolean
          ply?: number
          pot?: number
          resign_offered_by?: string | null
          room_code?: string | null
          stake?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          time_control_min?: number
          turn?: string
          turn_deadline?: string | null
          white_id?: string | null
          white_is_bot?: boolean
          white_time_ms?: number
          winner_id?: string | null
        }
        Relationships: []
      }
      chess_moves: {
        Row: {
          by_user: string | null
          created_at: string
          fen_after: string
          game_id: string
          id: string
          ply: number
          san: string
          uci: string
        }
        Insert: {
          by_user?: string | null
          created_at?: string
          fen_after: string
          game_id: string
          id?: string
          ply: number
          san: string
          uci: string
        }
        Update: {
          by_user?: string | null
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
      cms_content: {
        Row: {
          content: Json
          key: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          content?: Json
          key: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          content?: Json
          key?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
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
          afk_pause_for: string | null
          afk_pause_name: string | null
          afk_warning: Json | null
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
          pause_deadline: string | null
          pause_used: boolean
          paused: boolean
          paused_turn_remaining_s: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
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
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
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
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
        Relationships: [
          {
            foreignKeyName: "domino_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domino_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domino_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      domino_participants: {
        Row: {
          bot_intelligence: number
          bot_name: string | null
          display_name: string
          forfeited: boolean
          game_id: string
          id: string
          is_bot: boolean
          joined_at: string
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          bot_intelligence?: number
          bot_name?: string | null
          display_name: string
          forfeited?: boolean
          game_id: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          bot_intelligence?: number
          bot_name?: string | null
          display_name?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          is_bot?: boolean
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
          afk_pause_for: string | null
          afk_pause_name: string | null
          afk_warning: Json | null
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
          pause_deadline: string | null
          pause_used: boolean
          paused: boolean
          paused_turn_remaining_s: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
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
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
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
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
        Relationships: [
          {
            foreignKeyName: "fanorona_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fanorona_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fanorona_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      fanorona_participants: {
        Row: {
          bot_intelligence: number
          bot_name: string | null
          color: string
          display_name: string
          forfeited: boolean
          game_id: string
          id: string
          is_bot: boolean
          joined_at: string
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          bot_intelligence?: number
          bot_name?: string | null
          color: string
          display_name: string
          forfeited?: boolean
          game_id: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          bot_intelligence?: number
          bot_name?: string | null
          color?: string
          display_name?: string
          forfeited?: boolean
          game_id?: string
          id?: string
          is_bot?: boolean
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
      friendships: {
        Row: {
          addressee_id: string
          created_at: string
          id: string
          requester_id: string
          status: string
          updated_at: string
        }
        Insert: {
          addressee_id: string
          created_at?: string
          id?: string
          requester_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          addressee_id?: string
          created_at?: string
          id?: string
          requester_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      game_configs: {
        Row: {
          badge: string | null
          cover_url: string
          display_name: string
          instructions_dismissible: boolean
          max_online_capacity: number
          max_turn_skips: number
          rules_markdown: string
          slug: string
          tournament_join_timeout_secs: number
          turn_timer_seconds: number
          updated_at: string
        }
        Insert: {
          badge?: string | null
          cover_url?: string
          display_name: string
          instructions_dismissible?: boolean
          max_online_capacity?: number
          max_turn_skips?: number
          rules_markdown?: string
          slug: string
          tournament_join_timeout_secs?: number
          turn_timer_seconds?: number
          updated_at?: string
        }
        Update: {
          badge?: string | null
          cover_url?: string
          display_name?: string
          instructions_dismissible?: boolean
          max_online_capacity?: number
          max_turn_skips?: number
          rules_markdown?: string
          slug?: string
          tournament_join_timeout_secs?: number
          turn_timer_seconds?: number
          updated_at?: string
        }
        Relationships: []
      }
      game_invitations: {
        Row: {
          created_at: string
          expires_at: string
          game_id: string | null
          game_slug: string
          id: string
          message: string | null
          receiver_id: string
          room_code: string | null
          sender_id: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          expires_at?: string
          game_id?: string | null
          game_slug: string
          id?: string
          message?: string | null
          receiver_id: string
          room_code?: string | null
          sender_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          game_id?: string | null
          game_slug?: string
          id?: string
          message?: string | null
          receiver_id?: string
          room_code?: string | null
          sender_id?: string
          status?: string
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
      house_ledger: {
        Row: {
          amount: number
          commission_pct: number | null
          created_at: string
          entry_type: string
          game_id: string | null
          game_type: string
          id: string
          meta: Json | null
          note: string | null
          pot: number | null
          winner_id: string | null
        }
        Insert: {
          amount: number
          commission_pct?: number | null
          created_at?: string
          entry_type: string
          game_id?: string | null
          game_type: string
          id?: string
          meta?: Json | null
          note?: string | null
          pot?: number | null
          winner_id?: string | null
        }
        Update: {
          amount?: number
          commission_pct?: number | null
          created_at?: string
          entry_type?: string
          game_id?: string | null
          game_type?: string
          id?: string
          meta?: Json | null
          note?: string | null
          pot?: number | null
          winner_id?: string | null
        }
        Relationships: []
      }
      ludo_games: {
        Row: {
          afk_pause_for: string | null
          afk_pause_name: string | null
          afk_warning: Json | null
          auto_move: boolean
          bot_delay_for_stamp: string | null
          bot_delay_until: string | null
          commission_pct: number
          created_at: string
          current_turn: number
          dice_override: Json | null
          disconnect_until: Json
          finished_at: string | null
          host_id: string
          id: string
          is_private: boolean
          is_solo: boolean
          max_players: number
          mode: string
          pause_deadline: string | null
          pause_used: boolean
          paused: boolean
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          auto_move?: boolean
          bot_delay_for_stamp?: string | null
          bot_delay_until?: string | null
          commission_pct?: number
          created_at?: string
          current_turn?: number
          dice_override?: Json | null
          disconnect_until?: Json
          finished_at?: string | null
          host_id: string
          id?: string
          is_private?: boolean
          is_solo?: boolean
          max_players: number
          mode?: string
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          auto_move?: boolean
          bot_delay_for_stamp?: string | null
          bot_delay_until?: string | null
          commission_pct?: number
          created_at?: string
          current_turn?: number
          dice_override?: Json | null
          disconnect_until?: Json
          finished_at?: string | null
          host_id?: string
          id?: string
          is_private?: boolean
          is_solo?: boolean
          max_players?: number
          mode?: string
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
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
        Relationships: [
          {
            foreignKeyName: "ludo_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ludo_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ludo_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
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
          finish_rank: number | null
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
          finish_rank?: number | null
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
          finish_rank?: number | null
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
          expires_at: string | null
          id: string
          image_url: string | null
          link: string | null
          sort_order: number
          title: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          amount_ar?: number | null
          created_at?: string
          description?: string | null
          expires_at?: string | null
          id?: string
          image_url?: string | null
          link?: string | null
          sort_order?: number
          title: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          amount_ar?: number | null
          created_at?: string
          description?: string | null
          expires_at?: string | null
          id?: string
          image_url?: string | null
          link?: string | null
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
      petanque_boules: {
        Row: {
          angle: number | null
          dead: boolean
          distance: number
          game_id: string
          id: string
          lob: number | null
          play_order: number
          played_at: string
          player_id: string | null
          power: number | null
          round: number
          spin: number | null
          team: number
          x: number
          y: number
        }
        Insert: {
          angle?: number | null
          dead?: boolean
          distance?: number
          game_id: string
          id?: string
          lob?: number | null
          play_order: number
          played_at?: string
          player_id?: string | null
          power?: number | null
          round: number
          spin?: number | null
          team: number
          x: number
          y: number
        }
        Update: {
          angle?: number | null
          dead?: boolean
          distance?: number
          game_id?: string
          id?: string
          lob?: number | null
          play_order?: number
          played_at?: string
          player_id?: string | null
          power?: number | null
          round?: number
          spin?: number | null
          team?: number
          x?: number
          y?: number
        }
        Relationships: [
          {
            foreignKeyName: "petanque_boules_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "petanque_games"
            referencedColumns: ["id"]
          },
        ]
      }
      petanque_games: {
        Row: {
          boules_per_player: number
          cochonnet_x: number
          cochonnet_y: number
          created_at: string
          creator_id: string | null
          current_player_id: string | null
          current_round: number
          finished_at: string | null
          id: string
          is_private: boolean
          meta: Json
          mode: string
          pot: number
          prep_deadline: string | null
          room_code: string | null
          score_team0: number
          score_team1: number
          stake: number
          started_at: string | null
          status: string
          target_points: number
          turn_deadline: string | null
          winner_team: number | null
        }
        Insert: {
          boules_per_player?: number
          cochonnet_x?: number
          cochonnet_y?: number
          created_at?: string
          creator_id?: string | null
          current_player_id?: string | null
          current_round?: number
          finished_at?: string | null
          id?: string
          is_private?: boolean
          meta?: Json
          mode?: string
          pot?: number
          prep_deadline?: string | null
          room_code?: string | null
          score_team0?: number
          score_team1?: number
          stake?: number
          started_at?: string | null
          status?: string
          target_points?: number
          turn_deadline?: string | null
          winner_team?: number | null
        }
        Update: {
          boules_per_player?: number
          cochonnet_x?: number
          cochonnet_y?: number
          created_at?: string
          creator_id?: string | null
          current_player_id?: string | null
          current_round?: number
          finished_at?: string | null
          id?: string
          is_private?: boolean
          meta?: Json
          mode?: string
          pot?: number
          prep_deadline?: string | null
          room_code?: string | null
          score_team0?: number
          score_team1?: number
          stake?: number
          started_at?: string | null
          status?: string
          target_points?: number
          turn_deadline?: string | null
          winner_team?: number | null
        }
        Relationships: []
      }
      petanque_participants: {
        Row: {
          boules_left: number
          game_id: string
          id: string
          is_bot: boolean
          joined_at: string
          ready: boolean
          seat: number
          team: number
          user_id: string | null
        }
        Insert: {
          boules_left?: number
          game_id: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          seat: number
          team: number
          user_id?: string | null
        }
        Update: {
          boules_left?: number
          game_id?: string
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          seat?: number
          team?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "petanque_participants_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "petanque_games"
            referencedColumns: ["id"]
          },
        ]
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
      player_game_stats: {
        Row: {
          biggest_pot: number
          game_mode: string
          hands_played: number
          hands_won: number
          losses: number
          showdowns_won: number
          total_winnings: number
          updated_at: string
          user_id: string
          wins: number
        }
        Insert: {
          biggest_pot?: number
          game_mode: string
          hands_played?: number
          hands_won?: number
          losses?: number
          showdowns_won?: number
          total_winnings?: number
          updated_at?: string
          user_id: string
          wins?: number
        }
        Update: {
          biggest_pot?: number
          game_mode?: string
          hands_played?: number
          hands_won?: number
          losses?: number
          showdowns_won?: number
          total_winnings?: number
          updated_at?: string
          user_id?: string
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "player_game_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_game_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_game_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      poker_games: {
        Row: {
          afk_pause_for: string | null
          afk_pause_name: string | null
          afk_warning: Json | null
          big_blind: number
          commission_pct: number
          community_cards: number[]
          created_at: string
          created_by: string | null
          current_player: string | null
          finished_at: string | null
          hand_number: number
          id: string
          is_private: boolean
          max_buy_in: number
          max_players: number
          min_buy_in: number
          pause_deadline: string | null
          pause_used: boolean
          paused: boolean
          paused_turn_remaining_s: number | null
          phase: string
          pot: number
          rake_cap: number
          room_code: string | null
          side_pots: Json
          small_blind: number
          stake: number
          started_at: string | null
          state: Json
          status: string
          table_number: number | null
          tournament_id: string | null
          turn_deadline: string | null
          updated_at: string
          winner_id: string | null
        }
        Insert: {
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          big_blind?: number
          commission_pct?: number
          community_cards?: number[]
          created_at?: string
          created_by?: string | null
          current_player?: string | null
          finished_at?: string | null
          hand_number?: number
          id?: string
          is_private?: boolean
          max_buy_in?: number
          max_players?: number
          min_buy_in?: number
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
          phase?: string
          pot?: number
          rake_cap?: number
          room_code?: string | null
          side_pots?: Json
          small_blind?: number
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          table_number?: number | null
          tournament_id?: string | null
          turn_deadline?: string | null
          updated_at?: string
          winner_id?: string | null
        }
        Update: {
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          big_blind?: number
          commission_pct?: number
          community_cards?: number[]
          created_at?: string
          created_by?: string | null
          current_player?: string | null
          finished_at?: string | null
          hand_number?: number
          id?: string
          is_private?: boolean
          max_buy_in?: number
          max_players?: number
          min_buy_in?: number
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
          phase?: string
          pot?: number
          rake_cap?: number
          room_code?: string | null
          side_pots?: Json
          small_blind?: number
          stake?: number
          started_at?: string | null
          state?: Json
          status?: string
          table_number?: number | null
          tournament_id?: string | null
          turn_deadline?: string | null
          updated_at?: string
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "poker_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
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
        ]
      }
      poker_hand_history: {
        Row: {
          actions: Json
          board: number[]
          created_at: string
          game_id: string
          hand_number: number
          id: string
          players: Json
          pot: number
          rake: number
          tournament_id: string | null
          winner_id: string | null
        }
        Insert: {
          actions?: Json
          board?: number[]
          created_at?: string
          game_id: string
          hand_number: number
          id?: string
          players?: Json
          pot?: number
          rake?: number
          tournament_id?: string | null
          winner_id?: string | null
        }
        Update: {
          actions?: Json
          board?: number[]
          created_at?: string
          game_id?: string
          hand_number?: number
          id?: string
          players?: Json
          pot?: number
          rake?: number
          tournament_id?: string | null
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "poker_hand_history_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "poker_games"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_hand_history_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_hand_history_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "poker_hand_history_winner_id_fkey"
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
          bot_intelligence: number | null
          bot_name: string | null
          chips: number
          eliminated_at: string | null
          finish_place: number | null
          game_id: string
          hand_result: Json | null
          hole_cards: number[]
          id: string
          is_bot: boolean
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
          bot_intelligence?: number | null
          bot_name?: string | null
          chips?: number
          eliminated_at?: string | null
          finish_place?: number | null
          game_id: string
          hand_result?: Json | null
          hole_cards?: number[]
          id?: string
          is_bot?: boolean
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
          bot_intelligence?: number | null
          bot_name?: string | null
          chips?: number
          eliminated_at?: string | null
          finish_place?: number | null
          game_id?: string
          hand_result?: Json | null
          hole_cards?: number[]
          id?: string
          is_bot?: boolean
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
        ]
      }
      poker_tournament_blind_levels: {
        Row: {
          ante: number
          big_blind: number
          duration_seconds: number
          id: string
          level: number
          small_blind: number
          tournament_id: string
        }
        Insert: {
          ante?: number
          big_blind: number
          duration_seconds?: number
          id?: string
          level: number
          small_blind: number
          tournament_id: string
        }
        Update: {
          ante?: number
          big_blind?: number
          duration_seconds?: number
          id?: string
          level?: number
          small_blind?: number
          tournament_id?: string
        }
        Relationships: []
      }
      poker_tournament_tables: {
        Row: {
          created_at: string
          game_id: string
          id: string
          is_final_table: boolean
          table_number: number
          tournament_id: string
        }
        Insert: {
          created_at?: string
          game_id: string
          id?: string
          is_final_table?: boolean
          table_number: number
          tournament_id: string
        }
        Update: {
          created_at?: string
          game_id?: string
          id?: string
          is_final_table?: boolean
          table_number?: number
          tournament_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "poker_tournament_tables_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: true
            referencedRelation: "poker_games"
            referencedColumns: ["id"]
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
          email: string | null
          first_deposit_amount: number | null
          first_deposit_at: string | null
          first_game_at: string | null
          id: string
          is_admin: boolean
          is_banned: boolean
          is_bot: boolean
          is_premium: boolean
          last_daily_claim: string | null
          leaderboard_hidden: boolean
          leaderboard_rank_override: number | null
          phone: string | null
          phone_number: string | null
          phone_verification_code: string | null
          phone_verification_code_hash: string | null
          phone_verification_requested_at: string | null
          phone_verified: boolean
          player_level: number
          pseudo: string
          referral_code: string
          referral_stake_count: number
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
          email?: string | null
          first_deposit_amount?: number | null
          first_deposit_at?: string | null
          first_game_at?: string | null
          id: string
          is_admin?: boolean
          is_banned?: boolean
          is_bot?: boolean
          is_premium?: boolean
          last_daily_claim?: string | null
          leaderboard_hidden?: boolean
          leaderboard_rank_override?: number | null
          phone?: string | null
          phone_number?: string | null
          phone_verification_code?: string | null
          phone_verification_code_hash?: string | null
          phone_verification_requested_at?: string | null
          phone_verified?: boolean
          player_level?: number
          pseudo: string
          referral_code: string
          referral_stake_count?: number
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
          email?: string | null
          first_deposit_amount?: number | null
          first_deposit_at?: string | null
          first_game_at?: string | null
          id?: string
          is_admin?: boolean
          is_banned?: boolean
          is_bot?: boolean
          is_premium?: boolean
          last_daily_claim?: string | null
          leaderboard_hidden?: boolean
          leaderboard_rank_override?: number | null
          phone?: string | null
          phone_number?: string | null
          phone_verification_code?: string | null
          phone_verification_code_hash?: string | null
          phone_verification_requested_at?: string | null
          phone_verified?: boolean
          player_level?: number
          pseudo?: string
          referral_code?: string
          referral_stake_count?: number
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
          afk_pause_for: string | null
          afk_pause_name: string | null
          afk_warning: Json | null
          commission_pct: number
          created_at: string
          created_by: string | null
          current_turn: number
          finished_at: string | null
          game_mode: string
          id: string
          is_private: boolean
          joker_mode: string
          max_players: number
          pause_deadline: string | null
          pause_used: boolean
          paused: boolean
          paused_turn_remaining_s: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          commission_pct?: number
          created_at?: string
          created_by?: string | null
          current_turn?: number
          finished_at?: string | null
          game_mode?: string
          id?: string
          is_private?: boolean
          joker_mode?: string
          max_players?: number
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
          afk_pause_for?: string | null
          afk_pause_name?: string | null
          afk_warning?: Json | null
          commission_pct?: number
          created_at?: string
          created_by?: string | null
          current_turn?: number
          finished_at?: string | null
          game_mode?: string
          id?: string
          is_private?: boolean
          joker_mode?: string
          max_players?: number
          pause_deadline?: string | null
          pause_used?: boolean
          paused?: boolean
          paused_turn_remaining_s?: number | null
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
        Relationships: [
          {
            foreignKeyName: "rami_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rami_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rami_games_afk_pause_for_fkey"
            columns: ["afk_pause_for"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      rami_participants: {
        Row: {
          bot_intelligence: number
          bot_name: string | null
          display_name: string | null
          forfeited: boolean
          game_id: string
          hand_count: number
          id: string
          is_bot: boolean
          joined_at: string
          ready: boolean
          slot: number
          user_id: string | null
        }
        Insert: {
          bot_intelligence?: number
          bot_name?: string | null
          display_name?: string | null
          forfeited?: boolean
          game_id: string
          hand_count?: number
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          slot: number
          user_id?: string | null
        }
        Update: {
          bot_intelligence?: number
          bot_name?: string | null
          display_name?: string | null
          forfeited?: boolean
          game_id?: string
          hand_count?: number
          id?: string
          is_bot?: boolean
          joined_at?: string
          ready?: boolean
          slot?: number
          user_id?: string | null
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
          first_deposit_bonus_ar: number
          id: number
          max_daily_new_referrals: number
          require_first_deposit: boolean
          require_phone_verification: boolean
          self_referral_block: boolean
          stake_commission_max_matches: number
          stake_commission_pct: number
          tier_diamond_min: number
          tier_diamond_mult: number
          tier_gold_min: number
          tier_gold_mult: number
          tier_silver_min: number
          tier_silver_mult: number
          unlock_stake_matches: number
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
          first_deposit_bonus_ar?: number
          id?: number
          max_daily_new_referrals?: number
          require_first_deposit?: boolean
          require_phone_verification?: boolean
          self_referral_block?: boolean
          stake_commission_max_matches?: number
          stake_commission_pct?: number
          tier_diamond_min?: number
          tier_diamond_mult?: number
          tier_gold_min?: number
          tier_gold_mult?: number
          tier_silver_min?: number
          tier_silver_mult?: number
          unlock_stake_matches?: number
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
          first_deposit_bonus_ar?: number
          id?: number
          max_daily_new_referrals?: number
          require_first_deposit?: boolean
          require_phone_verification?: boolean
          self_referral_block?: boolean
          stake_commission_max_matches?: number
          stake_commission_pct?: number
          tier_diamond_min?: number
          tier_diamond_mult?: number
          tier_gold_min?: number
          tier_gold_mult?: number
          tier_silver_min?: number
          tier_silver_mult?: number
          unlock_stake_matches?: number
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
      tournament_entrants: {
        Row: {
          created_at: string
          display_name: string
          eliminated_round: number | null
          final_rank: number | null
          id: string
          is_bot: boolean
          status: string
          tournament_id: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          display_name: string
          eliminated_round?: number | null
          final_rank?: number | null
          id?: string
          is_bot?: boolean
          status?: string
          tournament_id: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          display_name?: string
          eliminated_round?: number | null
          final_rank?: number | null
          id?: string
          is_bot?: boolean
          status?: string
          tournament_id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tournament_entrants_tournament_id_fkey"
            columns: ["tournament_id"]
            isOneToOne: false
            referencedRelation: "tournaments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_entrants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_entrants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_player_stats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_entrants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_referral_stats"
            referencedColumns: ["referrer_id"]
          },
        ]
      }
      tournament_matches: {
        Row: {
          created_at: string
          deadline_at: string | null
          entrant_ids: string[]
          finished_at: string | null
          game_id: string | null
          id: string
          match_no: number
          phase: string
          pool_id: string | null
          round: number
          started_at: string | null
          status: string
          tournament_id: string
          winner_entrant_id: string | null
        }
        Insert: {
          created_at?: string
          deadline_at?: string | null
          entrant_ids: string[]
          finished_at?: string | null
          game_id?: string | null
          id?: string
          match_no?: number
          phase?: string
          pool_id?: string | null
          round?: number
          started_at?: string | null
          status?: string
          tournament_id: string
          winner_entrant_id?: string | null
        }
        Update: {
          created_at?: string
          deadline_at?: string | null
          entrant_ids?: string[]
          finished_at?: string | null
          game_id?: string | null
          id?: string
          match_no?: number
          phase?: string
          pool_id?: string | null
          round?: number
          started_at?: string | null
          status?: string
          tournament_id?: string
          winner_entrant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tournament_matches_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "tournament_pools"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_matches_tournament_id_fkey"
            columns: ["tournament_id"]
            isOneToOne: false
            referencedRelation: "tournaments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_matches_winner_entrant_id_fkey"
            columns: ["winner_entrant_id"]
            isOneToOne: false
            referencedRelation: "tournament_entrants"
            referencedColumns: ["id"]
          },
        ]
      }
      tournament_pool_entrants: {
        Row: {
          entrant_id: string
          id: string
          played: number
          points: number
          pool_id: string
          qualified: boolean
          wins: number
        }
        Insert: {
          entrant_id: string
          id?: string
          played?: number
          points?: number
          pool_id: string
          qualified?: boolean
          wins?: number
        }
        Update: {
          entrant_id?: string
          id?: string
          played?: number
          points?: number
          pool_id?: string
          qualified?: boolean
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "tournament_pool_entrants_entrant_id_fkey"
            columns: ["entrant_id"]
            isOneToOne: false
            referencedRelation: "tournament_entrants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tournament_pool_entrants_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "tournament_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      tournament_pools: {
        Row: {
          created_at: string
          id: string
          label: string
          status: string
          tournament_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          label: string
          status?: string
          tournament_id: string
        }
        Update: {
          created_at?: string
          id?: string
          label?: string
          status?: string
          tournament_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tournament_pools_tournament_id_fkey"
            columns: ["tournament_id"]
            isOneToOne: false
            referencedRelation: "tournaments"
            referencedColumns: ["id"]
          },
        ]
      }
      tournaments: {
        Row: {
          admin_prize_pool_ar: number
          auto_advance: boolean
          break_seconds: number
          break_until: string | null
          champion_entrant_id: string | null
          created_at: string
          created_by: string | null
          current_round: number
          description: string | null
          entry_fee_ar: number
          finished_at: string | null
          format: string
          game_slug: string
          id: string
          is_simulation: boolean
          lobby_minutes: number
          max_concurrent_matches: number
          max_players: number
          name: string
          platform_pct: number
          players_per_match: number
          pool_size: number
          prize_1_pct: number
          prize_2_pct: number
          prize_3_pct: number
          prize_pool_ar: number
          qualifiers_per_pool: number
          registration_closes_at: string | null
          stage: string
          started_at: string | null
          starts_at: string | null
          status: string
          total_rounds: number
          updated_at: string
          winners_count: number
        }
        Insert: {
          admin_prize_pool_ar?: number
          auto_advance?: boolean
          break_seconds?: number
          break_until?: string | null
          champion_entrant_id?: string | null
          created_at?: string
          created_by?: string | null
          current_round?: number
          description?: string | null
          entry_fee_ar?: number
          finished_at?: string | null
          format?: string
          game_slug?: string
          id?: string
          is_simulation?: boolean
          lobby_minutes?: number
          max_concurrent_matches?: number
          max_players?: number
          name: string
          platform_pct?: number
          players_per_match?: number
          pool_size?: number
          prize_1_pct?: number
          prize_2_pct?: number
          prize_3_pct?: number
          prize_pool_ar?: number
          qualifiers_per_pool?: number
          registration_closes_at?: string | null
          stage?: string
          started_at?: string | null
          starts_at?: string | null
          status?: string
          total_rounds?: number
          updated_at?: string
          winners_count?: number
        }
        Update: {
          admin_prize_pool_ar?: number
          auto_advance?: boolean
          break_seconds?: number
          break_until?: string | null
          champion_entrant_id?: string | null
          created_at?: string
          created_by?: string | null
          current_round?: number
          description?: string | null
          entry_fee_ar?: number
          finished_at?: string | null
          format?: string
          game_slug?: string
          id?: string
          is_simulation?: boolean
          lobby_minutes?: number
          max_concurrent_matches?: number
          max_players?: number
          name?: string
          platform_pct?: number
          players_per_match?: number
          pool_size?: number
          prize_1_pct?: number
          prize_2_pct?: number
          prize_3_pct?: number
          prize_pool_ar?: number
          qualifiers_per_pool?: number
          registration_closes_at?: string | null
          stage?: string
          started_at?: string | null
          starts_at?: string | null
          status?: string
          total_rounds?: number
          updated_at?: string
          winners_count?: number
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount: number
          created_at: string
          id: string
          meta: Json | null
          note: string | null
          ref_id: string | null
          type: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          meta?: Json | null
          note?: string | null
          ref_id?: string | null
          type: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          meta?: Json | null
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
      withdrawal_debts: {
        Row: {
          amount_ar: number
          created_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_ar?: number
          created_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_ar?: number
          created_at?: string
          updated_at?: string
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
          recipient_name: string | null
          status: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          method: string
          processed_at?: string | null
          recipient_name?: string | null
          status?: Database["public"]["Enums"]["tx_status"]
          user_id: string
          user_phone: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          method?: string
          processed_at?: string | null
          recipient_name?: string | null
          status?: Database["public"]["Enums"]["tx_status"]
          user_id?: string
          user_phone?: string
        }
        Relationships: []
      }
    }
    Views: {
      v_finance_daily: {
        Row: {
          bonuses_adjustments: number | null
          commissions: number | null
          day: string | null
          deposits: number | null
          payouts: number | null
          refunds: number | null
          stakes: number | null
          tx_count: number | null
          withdrawals: number | null
        }
        Relationships: []
      }
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
      _admin_has_active_session: {
        Args: { _exclude_user?: string }
        Returns: boolean
      }
      _admin_log: {
        Args: { _action: string; _new: Json; _old: Json; _target: string }
        Returns: undefined
      }
      _admin_notify_others: {
        Args: { _action: string; _payload: Json }
        Returns: undefined
      }
      _admin_security_housekeeping: { Args: never; Returns: undefined }
      _afk_forfeit_player: {
        Args: { _game_id: string; _slug: string; _uid: string }
        Returns: undefined
      }
      _assert_solo_bot_enabled: { Args: never; Returns: undefined }
      _auto_advance_overdue_turns: { Args: never; Returns: undefined }
      _auto_cancel_open_games: { Args: never; Returns: undefined }
      _auto_resume_paused_games: { Args: never; Returns: undefined }
      _chess_ephemeral_bot: { Args: { _pseudo: string }; Returns: string }
      _chess_gen_code: { Args: never; Returns: string }
      _chess_payout: {
        Args: { _draw: boolean; _game_id: string; _winner: string }
        Returns: undefined
      }
      _chess_settle: {
        Args: { _draw: boolean; _id: string; _reason: string; _winner: string }
        Returns: undefined
      }
      _chess_sync_fen_turn: {
        Args: { _fen: string; _turn: string }
        Returns: string
      }
      _domino_active_humans: { Args: { _gid: string }; Returns: number }
      _domino_arm_bot_think: {
        Args: { _game_id: string; _slot: number; _state: Json }
        Returns: Json
      }
      _domino_auto_draw: { Args: { _game_id: string }; Returns: boolean }
      _domino_autoplay_bots: { Args: { _game_id: string }; Returns: undefined }
      _domino_bot_pick_move: {
        Args: { _intel: number; _slot: number; _state: Json }
        Returns: Json
      }
      _domino_bot_step: { Args: { _game_id: string }; Returns: undefined }
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
      _domino_lock_game: { Args: { _game_id: string }; Returns: undefined }
      _domino_lowest_pip_slot: {
        Args: { _game_id: string; _state: Json }
        Returns: number
      }
      _domino_next_playable_slot: {
        Args: { _from_slot: number; _game_id: string; _state: Json }
        Returns: number
      }
      _domino_next_round: { Args: { _game_id: string }; Returns: undefined }
      _domino_normalize_board: { Args: { _board: Json }; Returns: Json }
      _domino_place_first: { Args: { _game_id: string }; Returns: undefined }
      _domino_play_as: {
        Args: { _game_id: string; _move: Json; _slot: number }
        Returns: undefined
      }
      _domino_purge: { Args: { _game_id: string }; Returns: undefined }
      _domino_required_starter_slot: {
        Args: { _game_id: string; _state: Json }
        Returns: number
      }
      _domino_slot_has_playable: {
        Args: { _slot: number; _state: Json }
        Returns: boolean
      }
      _domino_start: { Args: { _game_id: string }; Returns: undefined }
      _domino_turn_state: {
        Args: { _state: Json; _turn_seconds: number }
        Returns: Json
      }
      _domino_visible: { Args: { _game_id: string }; Returns: boolean }
      _end_bot_only_games: { Args: never; Returns: undefined }
      _fanorona_apply_move: {
        Args: { _game_id: string; _move: Json; _slot: number }
        Returns: undefined
      }
      _fanorona_axis: { Args: { _dc: number; _dr: number }; Returns: string }
      _fanorona_bot_pick_move: { Args: { _game_id: string }; Returns: Json }
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
      _fanorona_draw_refund: { Args: { _game_id: string }; Returns: undefined }
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
      _finance_tests_cleanup: { Args: { _ids: string[] }; Returns: undefined }
      _game_cfg: {
        Args: { _slug: string }
        Returns: {
          max_turn_skips: number
          turn_timer_seconds: number
        }[]
      }
      _game_resume_internal: {
        Args: { _game_id: string; _slug: string }
        Returns: undefined
      }
      _game_visible: { Args: { _game_id: string }; Returns: boolean }
      _gen_room_code: { Args: never; Returns: string }
      _is_game_participant: {
        Args: { _game_id: string; _user_id: string }
        Returns: boolean
      }
      _is_valid_email: { Args: { _raw: string }; Returns: boolean }
      _is_valid_http_url: { Args: { _raw: string }; Returns: boolean }
      _is_valid_mg_phone: { Args: { _raw: string }; Returns: boolean }
      _log_admin_action: {
        Args: {
          _action: string
          _payload?: Json
          _target_id: string
          _target_type: string
        }
        Returns: undefined
      }
      _ludo_active_humans: { Args: { _game_id: string }; Returns: number }
      _ludo_advance_turn: {
        Args: { _game_id: string; _last_event: string; _new_slot: number }
        Returns: Json
      }
      _ludo_auto_move: {
        Args: { _game_id: string; _slot: number }
        Returns: boolean
      }
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
      _ludo_playable_pawns: {
        Args: { _dice: number; _pawns: Json; _slot: number }
        Returns: Json
      }
      _ludo_purge: { Args: { _game_id: string }; Returns: undefined }
      _ludo_push_move: {
        Args: { _entry: Json; _game_id: string }
        Returns: undefined
      }
      _ludo_start_for: {
        Args: { _game_id: string; _slot: number }
        Returns: number
      }
      _ludo_start_idx: { Args: { _slot: number }; Returns: number }
      _maybe_end_bot_only_domino: {
        Args: { _game_id: string }
        Returns: undefined
      }
      _maybe_end_bot_only_fanorona: {
        Args: { _game_id: string }
        Returns: undefined
      }
      _maybe_end_bot_only_ludo: {
        Args: { _game_id: string }
        Returns: undefined
      }
      _maybe_end_bot_only_rami: {
        Args: { _game_id: string }
        Returns: undefined
      }
      _petanque_distance: {
        Args: { ax: number; ay: number; bx: number; by_: number }
        Returns: number
      }
      _petanque_end_round: { Args: { _game_id: string }; Returns: undefined }
      _petanque_next_player: { Args: { _game_id: string }; Returns: string }
      _petanque_settle: { Args: { _game_id: string }; Returns: undefined }
      _petanque_simulate: {
        Args: {
          p_angle: number
          p_lob: number
          p_power: number
          p_spin: number
          p_throw_y: number
        }
        Returns: {
          dead: boolean
          final_x: number
          final_y: number
        }[]
      }
      _poker_award: {
        Args: { _gid: string; _winner: string }
        Returns: undefined
      }
      _poker_bot_act: { Args: { _gid: string }; Returns: boolean }
      _poker_deal_hand: { Args: { _gid: string }; Returns: undefined }
      _poker_end_hand: { Args: { _gid: string }; Returns: undefined }
      _poker_hand_strength: {
        Args: { community: number[]; hole: number[] }
        Returns: number
      }
      _poker_next_street: { Args: { _gid: string }; Returns: undefined }
      _poker_showdown: { Args: { _gid: string }; Returns: undefined }
      _rami_active_humans: { Args: { _gid: string }; Returns: number }
      _rami_all_discards: { Args: { _state: Json }; Returns: number[] }
      _rami_autoplay_bots: { Args: { _game_id: string }; Returns: undefined }
      _rami_check_win:
        | { Args: { _key: string; _state: Json }; Returns: boolean }
        | { Args: { _state: Json; _uid: string }; Returns: boolean }
      _rami_discards_map: { Args: { _state: Json }; Returns: Json }
      _rami_gen_code: { Args: never; Returns: string }
      _rami_is_joker: {
        Args: { _c: number; _mode: string; _rj: number }
        Returns: boolean
      }
      _rami_is_seven: {
        Args: { _cards: number[]; _mode: string; _rj: number }
        Returns: boolean
      }
      _rami_jarr: { Args: { _v: Json }; Returns: number[] }
      _rami_jset: { Args: { _a: number[] }; Returns: Json }
      _rami_last_discarder: { Args: { _state: Json }; Returns: string }
      _rami_meld_type: {
        Args: { _cards: number[]; _mode: string; _rj: number }
        Returns: string
      }
      _rami_normalize_state: { Args: { _state: Json }; Returns: Json }
      _rami_remove_one: {
        Args: { _arr: number[]; _v: number }
        Returns: number[]
      }
      _rami_reshuffle: { Args: { _state: Json }; Returns: Json }
      _rami_validate_meld: { Args: { _cards: number[] }; Returns: boolean }
      _rami_visible: { Args: { _game_id: string }; Returns: boolean }
      _t_build_round: {
        Args: { _ids: string[]; _round: number; _tid: string }
        Returns: undefined
      }
      _t_draw_pools: { Args: { _tid: string }; Returns: undefined }
      _t_finish: { Args: { _tid: string }; Returns: undefined }
      _t_launch_match: { Args: { _match_id: string }; Returns: undefined }
      _t_match_finish: {
        Args: { _match_id: string; _winner: string }
        Returns: undefined
      }
      _t_next_round: { Args: { _tid: string }; Returns: undefined }
      _t_notify: {
        Args: { _body: string; _entrant: string; _link: string; _title: string }
        Returns: undefined
      }
      _t_pool_rank: {
        Args: { _pool_id: string }
        Returns: {
          entrant_id: string
          pos: number
        }[]
      }
      _t_pool_recompute: { Args: { _pool_id: string }; Returns: undefined }
      _t_sim_resolve: { Args: { _tid: string }; Returns: number }
      _tourn_assign_ludo_waves: {
        Args: { _round: number; _tid: string }
        Returns: undefined
      }
      _tourn_launch_ludo_match: { Args: { _match_id: string }; Returns: string }
      _tourn_ludo_active_count: { Args: never; Returns: number }
      _tourn_ludo_limit: { Args: never; Returns: number }
      _tourn_wave_for: {
        Args: { _idx: number; _limit: number; _total: number }
        Returns: number
      }
      _tpool_notify: {
        Args: { _body: string; _tid: string; _title: string; _uids: string[] }
        Returns: undefined
      }
      _try_unlock_referral: { Args: { _uid: string }; Returns: undefined }
      _validate_app_settings: {
        Args: { _row: Database["public"]["Tables"]["app_settings"]["Row"] }
        Returns: string
      }
      accept_terms: { Args: never; Returns: undefined }
      admin_activate_alias: { Args: { p_alias_id: string }; Returns: undefined }
      admin_activate_persona: {
        Args: { p_avatar_url?: string; p_pseudo: string }
        Returns: undefined
      }
      admin_add_bot: {
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
      admin_align_balances: {
        Args: never
        Returns: {
          new_balance: number
          old_balance: number
          pseudo: string
          tx_delta: number
          user_id: string
        }[]
      }
      admin_announcement_create: {
        Args: {
          _body?: string
          _image_url?: string
          _link?: string
          _link_label?: string
          _title: string
        }
        Returns: string
      }
      admin_announcement_toggle: {
        Args: { _active: boolean; _id: string }
        Returns: undefined
      }
      admin_audit_unlogged_changes: {
        Args: { _hours?: number }
        Returns: {
          audit_delta: number
          pseudo: string
          tx_delta: number
          unlogged: number
          user_id: string
        }[]
      }
      admin_auto_process_expired_matches: {
        Args: { _tid: string }
        Returns: Json
      }
      admin_auto_start_ready_matches: { Args: { _tid: string }; Returns: Json }
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
      admin_check_lockout: {
        Args: { _user_id: string }
        Returns: {
          locked: boolean
          locked_until: string
          reason: string
        }[]
      }
      admin_close_expired_registrations: { Args: never; Returns: Json }
      admin_create_community: {
        Args: { _image_url?: string; _name: string }
        Returns: string
      }
      admin_create_session: {
        Args: {
          _approval_id: string
          _ip: unknown
          _mfa_verified: boolean
          _user_agent: string
        }
        Returns: Json
      }
      admin_dashboard_kpis: { Args: never; Returns: Json }
      admin_dashboard_totals: { Args: never; Returns: Json }
      admin_deactivate_persona: { Args: never; Returns: undefined }
      admin_delete_alias: { Args: { p_alias_id: string }; Returns: undefined }
      admin_delete_community: { Args: { _room_id: string }; Returns: undefined }
      admin_delete_game: { Args: { _game_id: string }; Returns: undefined }
      admin_dm_send: {
        Args: { _message: string; _user_id: string }
        Returns: string
      }
      admin_finance_kpi: { Args: never; Returns: Json }
      admin_force_finish_game: {
        Args: { _game_id: string; _winner_id?: string }
        Returns: undefined
      }
      admin_force_match_result: {
        Args: { _mid: string; _reason: string; _winner_id: string }
        Returns: Json
      }
      admin_forfeit_match_player: {
        Args: { _loser_id: string; _mid: string; _reason: string }
        Returns: Json
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
      admin_get_forfeit_cron_info: { Args: never; Returns: Json }
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
      admin_get_intervention_dashboard: { Args: never; Returns: Json }
      admin_get_persona: {
        Args: never
        Returns: {
          activated_at: string
          is_active: boolean
          persona_avatar: string
          persona_pseudo: string
          real_avatar_url: string
          real_pseudo: string
        }[]
      }
      admin_house_income: {
        Args: { _since?: string }
        Returns: {
          commission_total: number
          entries: number
          game_type: string
          house_win_total: number
        }[]
      }
      admin_join_game: {
        Args: { _display_name?: string; _game_id: string }
        Returns: undefined
      }
      admin_leaderboard_list: {
        Args: { _limit?: number; _period?: string; _slug?: string }
        Returns: {
          avatar_url: string
          hidden: boolean
          name: string
          rank_override: number
          total_won: number
          user_id: string
          wins: number
        }[]
      }
      admin_list_aliases: {
        Args: never
        Returns: {
          avatar_url: string
          created_at: string
          id: string
          is_active: boolean
          pseudo: string
        }[]
      }
      admin_list_all_active_sessions: {
        Args: never
        Returns: {
          admin_name: string
          created_at: string
          expires_at: string
          id: string
          ip: unknown
          is_me: boolean
          last_seen_at: string
          mfa_verified: boolean
          override_reason: string
          user_agent: string
          user_id: string
        }[]
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
      admin_list_my_sessions: {
        Args: never
        Returns: {
          created_at: string
          expires_at: string
          id: string
          ip: unknown
          last_seen_at: string
          mfa_verified: boolean
          override_reason: string
          revoke_reason: string
          revoked_at: string
          user_agent: string
        }[]
      }
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
      admin_manual_payout: {
        Args: { _amount: number; _reason: string; _uid: string }
        Returns: Json
      }
      admin_offer_delete: { Args: { _id: string }; Returns: undefined }
      admin_offer_upsert: {
        Args: {
          _active: boolean
          _description: string
          _expires_at: string
          _id: string
          _image_url: string
          _link: string
          _title: string
        }
        Returns: string
      }
      admin_override_login: {
        Args: { _ip: unknown; _reason: string; _user_agent: string }
        Returns: Json
      }
      admin_override_match_winner: {
        Args: { _mid: string; _reason: string; _winner_id: string }
        Returns: Json
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
      admin_reconcile_balances: {
        Args: never
        Returns: {
          balance: number
          diff: number
          pseudo: string
          tx_sum: number
          user_id: string
        }[]
      }
      admin_record_login_attempt: {
        Args: {
          _ip: unknown
          _reason: string
          _success: boolean
          _ua: string
          _user_id: string
        }
        Returns: Json
      }
      admin_refund_game: { Args: { _game_id: string }; Returns: undefined }
      admin_reply_support: {
        Args: { _id: string; _reply: string }
        Returns: undefined
      }
      admin_request_login_approval: {
        Args: { _ip: unknown; _user_agent: string }
        Returns: Json
      }
      admin_reset_all_terms: { Args: never; Returns: number }
      admin_resolve_claim: {
        Args: { _cid: string; _comment?: string; _status: string }
        Returns: Json
      }
      admin_resolve_fraud_flag: {
        Args: { _flag_id: string; _pay_anyway?: boolean; _resolution: string }
        Returns: undefined
      }
      admin_respond_login_approval: {
        Args: { _decision: string; _request_id: string }
        Returns: Json
      }
      admin_revoke_all_other_sessions: { Args: never; Returns: number }
      admin_revoke_any_session: {
        Args: { _reason: string; _session_id: string }
        Returns: boolean
      }
      admin_revoke_session: {
        Args: { _reason: string; _session_id: string }
        Returns: undefined
      }
      admin_save_alias: {
        Args: { p_avatar_url?: string; p_pseudo: string }
        Returns: string
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
      admin_send_email_otp: { Args: never; Returns: Json }
      admin_set_daily_bonus: {
        Args: { _amount_ar: number; _enabled: boolean; _streak_bonus?: boolean }
        Returns: undefined
      }
      admin_set_forfeit_cron_interval: {
        Args: { _seconds: number }
        Returns: Json
      }
      admin_set_leaderboard_hidden: {
        Args: { _hidden: boolean; _user_id: string }
        Returns: undefined
      }
      admin_set_leaderboard_rank: {
        Args: { _rank: number; _user_id: string }
        Returns: undefined
      }
      admin_set_pause: {
        Args: { _message: string; _paused: boolean }
        Returns: undefined
      }
      admin_set_reward_distribution: {
        Args: {
          _first_pct: number
          _platform_pct: number
          _second_pct: number
          _third_pct: number
          _tid: string
        }
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
          active_users: number
          commission: number
          day: string
          deposits: number
          games_finished: number
          new_users: number
          stakes: number
          wins: number
          withdrawals: number
        }[]
      }
      admin_suspend_player: {
        Args: {
          _add_warning?: boolean
          _hours: number
          _reason: string
          _uid: string
        }
        Returns: Json
      }
      admin_top_referrers: {
        Args: never
        Returns: {
          phone: string
          pseudo: string
          referral_code: string
          referral_count: number
          referrer_id: string
          total_earned: number
        }[]
      }
      admin_tournament_add_bots: {
        Args: { _count: number; _tid: string }
        Returns: undefined
      }
      admin_tournament_cancel: {
        Args: { _reason?: string; _tid: string }
        Returns: undefined
      }
      admin_tournament_create: {
        Args: {
          _admin_prize_pool_ar: number
          _description?: string
          _entry_fee_ar: number
          _format: string
          _game_slug: string
          _lobby_minutes?: number
          _max_concurrent?: number
          _max_players: number
          _name: string
          _p1: number
          _p2: number
          _p3: number
          _players_per_match: number
          _pool_size?: number
          _qualifiers_per_pool?: number
          _registration_closes_at?: string
          _starts_at?: string
          _winners_count: number
        }
        Returns: string
      }
      admin_tournament_delay: {
        Args: { _minutes: number; _tid: string }
        Returns: undefined
      }
      admin_tournament_delete: { Args: { _tid: string }; Returns: undefined }
      admin_tournament_force_winner: {
        Args: { _entrant_id: string; _match_id: string }
        Returns: undefined
      }
      admin_tournament_next_stage: {
        Args: { _tid: string }
        Returns: undefined
      }
      admin_tournament_set_auto: {
        Args: { _auto: boolean; _tid: string }
        Returns: undefined
      }
      admin_tournament_set_break: {
        Args: { _seconds: number; _tid: string }
        Returns: undefined
      }
      admin_tournament_set_status: {
        Args: { _status: string; _tid: string }
        Returns: undefined
      }
      admin_tournament_simulate: {
        Args: { _max_steps?: number; _tid: string }
        Returns: Json
      }
      admin_tournament_simulate_new: {
        Args: {
          _format?: string
          _game_slug?: string
          _players?: number
          _players_per_match?: number
          _pool_size?: number
          _qualifiers_per_pool?: number
        }
        Returns: Json
      }
      admin_tournament_start: { Args: { _tid: string }; Returns: undefined }
      admin_update_bug_report: {
        Args: { _admin_note?: string; _id: string; _status: string }
        Returns: undefined
      }
      admin_update_cms_content: {
        Args: { _content: Json; _key: string }
        Returns: {
          content: Json
          key: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "cms_content"
          isOneToOne: true
          isSetofReturn: false
        }
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
          _enabled?: boolean
          _max_daily?: number
          _require_phone?: boolean
          _stake_commission_max_matches?: number
          _stake_commission_pct?: number
        }
        Returns: undefined
      }
      admin_update_settings: {
        Args: {
          _admin_label: string
          _admin_phone: string
          _airtel_name?: string
          _airtel_phone?: string
          _game_commission_pct: number
          _min_deposit: number
          _min_withdraw: number
          _mvola_name?: string
          _mvola_phone?: string
          _orange_name?: string
          _orange_phone?: string
          _referral_pct: number
          _signup_bonus: number
          _withdrawal_fee_pct?: number
        }
        Returns: undefined
      }
      admin_user_history: { Args: { _user_id: string }; Returns: Json }
      admin_validate_round: { Args: { _tid: string }; Returns: Json }
      admin_validate_session: { Args: { _fingerprint: string }; Returns: Json }
      admin_verify_email_otp: { Args: { _code: string }; Returns: Json }
      admin_verify_phone: {
        Args: { _approve: boolean; _user_id: string }
        Returns: undefined
      }
      can_access_realtime_topic: { Args: { _topic: string }; Returns: boolean }
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
      check_pseudo_availability: { Args: { _pseudo: string }; Returns: boolean }
      check_pseudo_available: { Args: { p_pseudo: string }; Returns: boolean }
      chess_accept_draw: { Args: { _id: string }; Returns: undefined }
      chess_add_bot: {
        Args: { _difficulty?: string; _game_id: string }
        Returns: undefined
      }
      chess_auto_end: {
        Args: { _draw: boolean; _game_id: string; _winner: string }
        Returns: undefined
      }
      chess_bot_play: {
        Args: {
          _elapsed_ms?: number
          _fen_after: string
          _id: string
          _san: string
          _uci: string
        }
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
      chess_create_friends: {
        Args: { _color?: string; _time_min?: number }
        Returns: {
          code: string
          id: string
        }[]
      }
      chess_create_solo: {
        Args: { _color?: string; _difficulty?: number; _time_min?: number }
        Returns: string
      }
      chess_create_stake: {
        Args: { _color?: string; _stake: number; _time_min?: number }
        Returns: string
      }
      chess_decline_draw: { Args: { _game_id: string }; Returns: undefined }
      chess_draw_finalize: { Args: { _game_id: string }; Returns: undefined }
      chess_draw_pick_color: {
        Args: { _color: string; _game_id: string }
        Returns: undefined
      }
      chess_finish: {
        Args: { _draw: boolean; _id: string; _reason: string; _winner: string }
        Returns: undefined
      }
      chess_join: { Args: { _game_id: string }; Returns: string }
      chess_join_friends: { Args: { _code: string }; Returns: string }
      chess_join_stake: { Args: { _id: string }; Returns: string }
      chess_offer_draw: { Args: { _id: string }; Returns: undefined }
      chess_play: {
        Args: {
          _elapsed_ms?: number
          _fen_after: string
          _id: string
          _san: string
          _uci: string
        }
        Returns: undefined
      }
      chess_request_or_accept_draw: {
        Args: { _game_id: string }
        Returns: undefined
      }
      chess_resign: { Args: { _id: string }; Returns: undefined }
      chess_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      chess_start_solo_bot: {
        Args: { _color?: string; _difficulty?: string }
        Returns: string
      }
      chess_tick: { Args: { _id: string }; Returns: undefined }
      chess_tick_all: { Args: never; Returns: number }
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
        Args: { _max_players: number; _mode?: string; _stake: number }
        Returns: string
      }
      credit_user_balance: {
        Args: {
          _amount: number
          _meta?: Json
          _note?: string
          _ref_id?: string
          _type: string
          _user_id: string
        }
        Returns: number
      }
      debit_user_balance: {
        Args: {
          _amount: number
          _meta?: Json
          _note?: string
          _ref_id?: string
          _type: string
          _user_id: string
        }
        Returns: number
      }
      delete_my_account: { Args: never; Returns: undefined }
      domino_add_bot: {
        Args: { _bot_name?: string; _game_id: string }
        Returns: undefined
      }
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
      domino_play_and_bot: {
        Args: { _game_id: string; _move: Json }
        Returns: undefined
      }
      domino_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      domino_start_solo_bot: {
        Args: {
          _difficulty?: string
          _draw_mode?: string
          _first_tile_rule?: string
          _max_players?: number
          _target_score?: number
        }
        Returns: string
      }
      domino_tick: { Args: { _game_id: string }; Returns: undefined }
      domino_tick_all: { Args: never; Returns: undefined }
      fanorona_add_bot: {
        Args: { _bot_name?: string; _game_id: string }
        Returns: string
      }
      fanorona_bot_play: { Args: { _game_id: string }; Returns: undefined }
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
      fanorona_play_as_bot: {
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
      fanorona_start_solo_bot: {
        Args: {
          _difficulty?: string
          _mandatory_capture?: boolean
          _variant?: string
        }
        Returns: string
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
      game_request_afk_pause: {
        Args: { _game_id: string; _slug: string }
        Returns: Json
      }
      game_request_pause: {
        Args: { _game_id: string; _slug: string }
        Returns: undefined
      }
      game_resume: {
        Args: { _game_id: string; _slug: string }
        Returns: undefined
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
      get_game_commission: { Args: { _game: string }; Returns: number }
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
      get_poker_hand_history: {
        Args: { _limit?: number; _user_id: string }
        Returns: {
          actions: Json
          board: number[]
          created_at: string
          game_id: string
          hand_number: number
          id: string
          players: Json
          pot: number
          rake: number
          tournament_id: string | null
          winner_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "poker_hand_history"
          isOneToOne: false
          isSetofReturn: true
        }
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
        Args: { _limit?: number; _period?: string; _slug?: string }
        Returns: {
          avatar_url: string
          name: string
          rank: number
          total_won: number
          user_id: string
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
      list_players_for_dm:
        | {
            Args: never
            Returns: {
              avatar_url: string
              id: string
              pseudo: string
            }[]
          }
        | {
            Args: { _limit?: number; _search?: string }
            Returns: {
              avatar_url: string
              id: string
              pseudo: string
              unique_code: string
            }[]
          }
      list_public_open_games: {
        Args: never
        Returns: {
          created_at: string
          game_slug: string
          id: string
          is_private: boolean
          max_players: number
          players_count: number
          pot: number
          room_code: string
          stake: number
        }[]
      }
      list_tournaments: {
        Args: { _game_slug?: string; _limit?: number; _status?: string }
        Returns: {
          admin_prize_pool_ar: number
          auto_advance: boolean
          break_seconds: number
          break_until: string | null
          champion_entrant_id: string | null
          created_at: string
          created_by: string | null
          current_round: number
          description: string | null
          entry_fee_ar: number
          finished_at: string | null
          format: string
          game_slug: string
          id: string
          is_simulation: boolean
          lobby_minutes: number
          max_concurrent_matches: number
          max_players: number
          name: string
          platform_pct: number
          players_per_match: number
          pool_size: number
          prize_1_pct: number
          prize_2_pct: number
          prize_3_pct: number
          prize_pool_ar: number
          qualifiers_per_pool: number
          registration_closes_at: string | null
          stage: string
          started_at: string | null
          starts_at: string | null
          status: string
          total_rounds: number
          updated_at: string
          winners_count: number
        }[]
        SetofOptions: {
          from: "*"
          to: "tournaments"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      ludo_bot_step: { Args: { _game_id: string }; Returns: Json }
      ludo_check_timeout: { Args: { _game_id: string }; Returns: Json }
      ludo_cleanup_empty_rooms: { Args: never; Returns: number }
      ludo_create_friends_game: {
        Args: {
          _is_public?: boolean
          _max_players: number
          _mode?: string
          _stake: number
        }
        Returns: string
      }
      ludo_heartbeat: { Args: { _game_id: string }; Returns: undefined }
      ludo_join: { Args: { _game_id: string }; Returns: string }
      ludo_move: {
        Args: { _game_id: string; _pawn_idx: number }
        Returns: Json
      }
      ludo_pass: { Args: { _game_id: string }; Returns: Json }
      ludo_purge_unready_rooms: { Args: never; Returns: number }
      ludo_quit: { Args: { _game_id: string }; Returns: undefined }
      ludo_roll: { Args: { _game_id: string }; Returns: Json }
      ludo_set_auto_move: {
        Args: { _enabled: boolean; _game_id: string }
        Returns: undefined
      }
      ludo_set_display_name: {
        Args: { _game_id: string; _name: string }
        Returns: undefined
      }
      ludo_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      ludo_start_solo_bot: {
        Args: { _difficulty?: string; _max_players?: number }
        Returns: string
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
      petanque_add_bot: { Args: { _game_id: string }; Returns: undefined }
      petanque_bot_step: { Args: { _game_id: string }; Returns: undefined }
      petanque_create: {
        Args: { p_public?: boolean; p_stake?: number }
        Returns: string
      }
      petanque_join: { Args: { _game_id: string }; Returns: undefined }
      petanque_join_code: { Args: { _code: string }; Returns: string }
      petanque_leave: { Args: { _game_id: string }; Returns: undefined }
      petanque_set_ready: {
        Args: { _game_id: string; _ready: boolean }
        Returns: undefined
      }
      petanque_throw: {
        Args: {
          _angle: number
          _game_id: string
          _lob: number
          _power: number
          _spin: number
        }
        Returns: Json
      }
      player_add_bot: {
        Args: { _bot_name?: string; _game_id: string }
        Returns: undefined
      }
      player_submit_claim: {
        Args: {
          _category: string
          _description: string
          _match_id: string
          _tournament_id: string
        }
        Returns: string
      }
      poker_action: {
        Args: { _action: string; _amount?: number; _game_id: string }
        Returns: undefined
      }
      poker_add_bot: {
        Args: { _bot_name?: string; _game_id: string }
        Returns: undefined
      }
      poker_autoplay_bots: { Args: { _game_id: string }; Returns: number }
      poker_create: {
        Args: {
          _big_blind?: number
          _buy_in?: number
          _commission?: number
          _max?: number
          _private?: boolean
          _rake_cap?: number
          _small_blind?: number
          _stake: number
        }
        Returns: string
      }
      poker_join: { Args: { _game_id: string }; Returns: string }
      poker_my_hole_cards: {
        Args: { _game_id: string }
        Returns: {
          hole_cards: number[]
          user_id: string
        }[]
      }
      poker_set_ready: {
        Args: { _game_id: string; _ready?: boolean }
        Returns: undefined
      }
      poker_start_next_hand: { Args: { _game_id: string }; Returns: undefined }
      poker_start_solo_bot: {
        Args: { _difficulty?: string; _max_players?: number }
        Returns: string
      }
      rami_add_bot:
        | { Args: { _bot_name?: string; _game_id: string }; Returns: undefined }
        | {
            Args: { _bot_name?: string; _difficulty?: string; _game_id: string }
            Returns: undefined
          }
      rami_claim_seven: { Args: { _game_id: string }; Returns: boolean }
      rami_create:
        | {
            Args: {
              _commission: number
              _joker_mode?: string
              _max: number
              _private: boolean
              _stake: number
            }
            Returns: string
          }
        | {
            Args: {
              _commission: number
              _game_mode?: string
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
      rami_join: { Args: { _game_id: string }; Returns: string }
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
      rami_start_solo_bot:
        | {
            Args: {
              _difficulty?: string
              _joker_mode?: string
              _max_players?: number
            }
            Returns: string
          }
        | {
            Args: {
              _difficulty?: string
              _game_mode?: string
              _joker_mode?: string
              _max_players?: number
            }
            Returns: string
          }
      rami_tick: { Args: { _game_id: string }; Returns: undefined }
      rami_unmeld: {
        Args: { _game_id: string; _meld_index: number }
        Returns: undefined
      }
      rami_validate_hand: {
        Args: { _discard_card: number; _game_id: string; _layout: Json }
        Returns: Json
      }
      request_password_reset: {
        Args: { _contact: string; _type: string }
        Returns: Json
      }
      request_phone_verification: { Args: { _phone: string }; Returns: string }
      request_withdrawal: {
        Args: {
          _amount: number
          _method: string
          _recipient_name?: string
          _user_phone: string
        }
        Returns: string
      }
      resolve_room_code: {
        Args: { _code: string }
        Returns: {
          game_id: string
          slug: string
        }[]
      }
      run_finance_tests: { Args: never; Returns: string }
      send_game_invite: {
        Args: {
          _game_id: string
          _recipient_id: string
          _sender_name?: string
          _slug: string
        }
        Returns: undefined
      }
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
      tournament_engine: { Args: { _tid: string }; Returns: undefined }
      tournament_engine_all: { Args: never; Returns: undefined }
      tournament_register: { Args: { _tid: string }; Returns: undefined }
      tournament_sim_report: { Args: { _tid: string }; Returns: Json }
      tournament_state: { Args: { _tid: string }; Returns: Json }
      tournament_unregister: { Args: { _tid: string }; Returns: undefined }
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
