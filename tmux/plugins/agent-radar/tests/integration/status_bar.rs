use crate::support::{Scenario, StatusBar, NOW};

#[test]
fn refresh_publishes_each_session_from_its_own_point_of_view() {
    let scenario = Scenario::new("status-sessions")
        .session("api", 100)
        .session("web", 200)
        .session("infra", 300)
        .session("notes", 400)
        .copilot_pane("%1", "api", 1, 1, 1000, "API Agent")
        .copilot_pane("%2", "web", 2, 1, 2000, "Web Agent")
        .copilot_pane("%3", "infra", 1, 2, 3000, "Infra Agent")
        .build();
    scenario.write_state("%1", "awaiting");
    scenario.write_done("%2", NOW + 5);
    scenario.write_state("%3", "working");

    scenario.run(&["--refresh"]);

    let api_value = scenario.session_option("api");
    let api = StatusBar::new(&api_value);
    assert!(api.has_icon_color("#f7768e"));
    assert!(api.has_pane("1.1", "#f7768e", false));
    assert!(api.has_current_session("1", "#f7768e"));
    assert!(api.has_session_signal("2", "#3fb950"));
    assert!(api.has_session_signal("3", "#e0af68"));

    let web_value = scenario.session_option("web");
    let web = StatusBar::new(&web_value);
    assert!(web.has_icon_color("#f7768e"));
    assert!(web.has_pane("2.1", "#3fb950", true));
    assert!(web.has_current_session("2", "#3fb950"));
    assert!(web.has_session_signal("1", "#f7768e"));

    let infra_value = scenario.session_option("infra");
    let infra = StatusBar::new(&infra_value);
    assert!(infra.has_pane("1.2", "#e0af68", false));
    assert!(infra.has_current_session("3", "#e0af68"));

    let notes_value = scenario.session_option("notes");
    let notes = StatusBar::new(&notes_value);
    assert!(notes.has_current_session("4", "#9ece6a"));
    assert!(!notes_value.contains("1.1 "));
    assert!(!notes_value.contains("2.1 "));
}

#[test]
fn session_without_agents_keeps_the_dim_icon_affordance() {
    let scenario = Scenario::new("status-empty").session("quiet", 100).build();

    let status = scenario.run_text(&["--tmux-status", "quiet"]);

    assert_eq!(
        status,
        "#[fg=#414868,bg=#24283b,bold]   #[bg=#050505,nobold]#[default]"
    );
}

#[test]
fn pane_cells_are_sorted_by_numeric_window_and_pane_position() {
    let scenario = Scenario::new("status-order")
        .session("work", 100)
        .copilot_pane("%1", "work", 1, 10, 1000, "Tenth")
        .copilot_pane("%2", "work", 1, 3, 2000, "Third")
        .copilot_pane("%3", "work", 2, 1, 3000, "Second Window")
        .build();
    scenario.write_state("%1", "idle");
    scenario.write_state("%2", "idle");
    scenario.write_state("%3", "idle");

    let status = scenario.run_text(&["--tmux-status", "work"]);

    let third = status.find("1.3 ").expect("third pane");
    let tenth = status.find("1.10 ").expect("tenth pane");
    let second_window = status.find("2.1 ").expect("second window pane");
    assert!(third < tenth && tenth < second_window, "{status}");
}
