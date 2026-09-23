# frozen_string_literal: true

module MultirdpLicenses
  # Einhängepunkte in die Redmine-Oberfläche (Namen in Redmine 6.1 geprüft).
  class Hooks < Redmine::Hook::ViewListener
    # Stylesheet für Freigabefenster und Formulare.
    render_on :view_layouts_base_html_head,
              partial: 'hooks/multirdp_licenses/html_head'

    # Freigabefenster für offene Geräteanfragen auf jeder Seite.
    render_on :view_layouts_base_body_bottom,
              partial: 'hooks/multirdp_licenses/body_bottom'

    # Link "Lizenzen" oben rechts in "Mein Konto".
    render_on :view_my_account_contextual,
              partial: 'hooks/multirdp_licenses/my_account_contextual'
  end
end
