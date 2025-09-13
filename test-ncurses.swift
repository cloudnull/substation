import Foundation
import CNCurses

func testNcurses() {
    print("Testing ncurses initialization...")

    let screen = initscr()
    if screen == nil {
        print("ERROR: initscr() returned nil")
        return
    }

    print("initscr() succeeded, screen = \(String(describing: screen))")

    // Try basic setup
    cbreak()
    noecho()

    // Get dimensions
    let rows = getmaxy(screen)
    let cols = getmaxx(screen)
    print("Screen dimensions: \(cols)x\(rows)")

    // Try to write something
    wmove(screen, 0, 0)
    waddstr(screen, "Hello from ncurses!")
    wrefresh(screen)

    // Wait a bit
    sleep(2)

    endwin()
    print("ncurses test completed successfully")
}

testNcurses()