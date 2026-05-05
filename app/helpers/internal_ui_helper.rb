# frozen_string_literal: true

module InternalUiHelper
  def bc_button_class(variant = :secondary)
    base = "inline-flex items-center justify-center rounded-md px-3 py-2 text-sm font-medium " \
           "transition-colors focus-visible:outline-none focus-visible:ring-2 " \
           "focus-visible:ring-[var(--bc-color-focus)] focus-visible:ring-offset-2 " \
           "disabled:pointer-events-none disabled:opacity-50"

    variants = {
      primary: "#{base} bg-[var(--bc-color-action)] text-white hover:bg-[var(--bc-color-action-hover)]",
      secondary: "#{base} border border-[var(--bc-color-border-strong)] bg-white text-[var(--bc-color-text)] hover:bg-[var(--bc-color-surface-muted)]",
      danger: "#{base} bg-red-700 text-white hover:bg-red-800",
      quiet: "#{base} text-[var(--bc-color-text-muted)] hover:bg-[var(--bc-color-surface-muted)] hover:text-[var(--bc-color-text)]",
      shell: "#{base} border border-white/15 bg-white/10 text-white hover:bg-white/16"
    }

    variants.fetch(variant.to_sym, variants[:secondary])
  end

  def bc_badge_class(variant = :neutral)
    base = "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"

    variants = {
      success: "#{base} bg-emerald-100 text-emerald-800",
      warning: "#{base} bg-amber-100 text-amber-900",
      danger: "#{base} bg-red-100 text-red-800",
      neutral: "#{base} bg-slate-100 text-slate-700"
    }

    variants.fetch(variant.to_sym, variants[:neutral])
  end

  def bc_nav_link_class(active: false, tone: :default)
    base = "rounded-md px-2.5 py-1.5 font-medium transition-colors focus-visible:outline-none " \
           "focus-visible:ring-2 focus-visible:ring-[var(--bc-color-focus)] focus-visible:ring-offset-2"

    tones = {
      default: if active
        "#{base} bg-[var(--bc-color-action)] text-white"
      else
        "#{base} text-[var(--bc-color-text-muted)] hover:bg-[var(--bc-color-surface-muted)] hover:text-[var(--bc-color-text)]"
      end,
      surface: if active
        "#{base} border border-[var(--bc-color-action)] bg-[var(--bc-color-action)] text-white shadow-sm"
      else
        "#{base} border border-[var(--bc-color-border-strong)] bg-white text-[var(--bc-color-text)] shadow-sm hover:bg-[var(--bc-color-surface-muted)]"
      end,
      shell: if active
        "#{base} bg-white text-slate-950 shadow-sm"
      else
        "#{base} text-slate-300 hover:bg-white/10 hover:text-white"
      end,
      command: if active
        "#{base} bg-white text-slate-950 shadow-sm"
      else
        "#{base} border border-white/12 bg-white/6 text-slate-200 hover:bg-white/12 hover:text-white"
      end
    }

    tones.fetch(tone.to_sym, tones[:default])
  end

  def bc_panel_class(tone: :default)
    base = "rounded border shadow-sm"

    tones = {
      default: "#{base} border-[var(--bc-color-border)] bg-[var(--bc-color-surface)]",
      muted: "#{base} border-[var(--bc-color-border)] bg-[var(--bc-color-surface-muted)]",
      warning: "#{base} border-amber-200 bg-amber-50"
    }

    tones.fetch(tone.to_sym, tones[:default])
  end

  def bc_status_banner_class(tone: :info)
    base = "rounded border px-4 py-3 text-sm"

    tones = {
      info: "#{base} border-[var(--bc-color-info-border)] bg-[var(--bc-color-info-bg)] text-[var(--bc-color-info-text)]",
      success: "#{base} border-[var(--bc-color-success-border)] bg-[var(--bc-color-success-bg)] text-[var(--bc-color-success-text)]",
      warning: "#{base} border-[var(--bc-color-warning-border)] bg-[var(--bc-color-warning-bg)] text-[var(--bc-color-warning-text)]",
      danger: "#{base} border-[var(--bc-color-danger-border)] bg-[var(--bc-color-danger-bg)] text-[var(--bc-color-danger-text)]"
    }

    tones.fetch(tone.to_sym, tones[:info])
  end
end
