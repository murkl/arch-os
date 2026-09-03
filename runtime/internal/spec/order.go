package spec

import (
	"fmt"
	"strings"
)

// order settles what runs when.
//
// Two rules, and no third: a task runs after every task of an earlier stage,
// and after whatever it named in `needs`. Everything else about the order is
// nobody's business — units that neither the stages nor a need put in sequence
// are independent, and they run in folder order so that the same module always
// produces the same list.
//
// Working it out here rather than keeping a list of steps somewhere means the
// two can never disagree: a folder added is a step added, and its place comes
// out of what it says about itself.
func order(units []*Task, stages []string) ([]*Task, error) {
	rank := make(map[string]int, len(stages))
	for i, s := range stages {
		if _, dup := rank[s]; dup {
			return nil, fmt.Errorf("stage %q is listed twice", s)
		}
		rank[s] = i
	}
	byID := make(map[string]*Task, len(units))
	for _, u := range units {
		if _, ok := rank[u.Stage]; !ok {
			return nil, fmt.Errorf("%s: no such stage: %s", u.id, u.Stage)
		}
		byID[u.id] = u
	}

	// Both rules as one thing to wait for, so a single pass settles them
	// together: what a unit needs, plus everything that came before its stage.
	waits := make(map[string]map[string]bool, len(units))
	for _, u := range units {
		waits[u.id] = map[string]bool{}
		for _, n := range u.Needs {
			dep, ok := byID[n]
			if !ok {
				return nil, fmt.Errorf("%s: needs unknown task: %s", u.id, n)
			}
			if n == u.id {
				return nil, fmt.Errorf("%s: needs itself", u.id)
			}
			if rank[dep.Stage] > rank[u.Stage] {
				return nil, fmt.Errorf("%s (stage %s) needs %s from the later stage %s",
					u.id, u.Stage, n, dep.Stage)
			}
			waits[u.id][n] = true
		}
		for _, other := range units {
			if rank[other.Stage] < rank[u.Stage] {
				waits[u.id][other.id] = true
			}
		}
	}

	out := make([]*Task, 0, len(units))
	done := map[string]bool{}
	for len(out) < len(units) {
		next := ready(units, waits, done)
		if next == nil {
			return nil, fmt.Errorf("tasks wait on each other: %s", strings.Join(waiting(units, done), ", "))
		}
		out = append(out, next)
		done[next.id] = true
	}
	return out, nil
}

// ready is the next unit that can run: the first one, in folder order, that is
// waiting for nothing any more.
//
// Stages need no comparing here. A unit of a later stage waits on every unit of
// every earlier one, so it cannot come up while any of those are still open —
// the stage order falls out of the same rule that orders needs.
func ready(units []*Task, waits map[string]map[string]bool, done map[string]bool) *Task {
	for _, u := range units {
		if done[u.id] {
			continue
		}
		if satisfied(waits[u.id], done) {
			return u
		}
	}
	return nil
}

func satisfied(waits map[string]bool, done map[string]bool) bool {
	for id := range waits {
		if !done[id] {
			return false
		}
	}
	return true
}

// waiting names what is left when nothing can run any more, which is the only
// way a cycle shows itself.
func waiting(units []*Task, done map[string]bool) []string {
	var left []string
	for _, u := range units {
		if !done[u.id] {
			left = append(left, u.id)
		}
	}
	return left
}
