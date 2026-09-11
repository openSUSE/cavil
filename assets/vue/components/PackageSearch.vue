<template>
  <div class="cavil-package-search-control">
    <button
      ref="trigger"
      type="button"
      class="nav-link cavil-package-search-trigger"
      aria-label="Find Package"
      :aria-expanded="expanded"
      aria-controls="cavil-package-search-popover"
      @click="toggleSearch"
    >
      Find Package
    </button>
    <div v-show="expanded" id="cavil-package-search-popover" class="cavil-package-search-popover">
      <form role="search" @submit.prevent="submit">
        <label for="cavil-package-search-input" class="visually-hidden">Find Package</label>
        <div class="cavil-package-search-anchor">
          <input
            id="cavil-package-search-input"
            ref="input"
            v-model="query"
            type="text"
            class="form-control cavil-search-input"
            placeholder="Package name"
            autocomplete="off"
            @input="onInput"
            @keydown.down.prevent="move(1)"
            @keydown.up.prevent="move(-1)"
            @keydown.enter.prevent="submit"
            @keydown.esc.prevent="dismiss"
            @focus="onFocus"
            @blur="onBlur"
          />
          <div v-show="open && suggestions.length > 0" class="autocomplete-container">
            <div class="autocomplete">
              <div
                v-for="(name, i) in suggestions"
                :key="name"
                :class="['autocomplete-item', {active: i === highlighted}]"
                @mousedown.prevent="choose(name)"
                @mousemove="highlighted = i"
              >
                {{ name }}
              </div>
            </div>
          </div>
        </div>
      </form>
    </div>
  </div>
</template>

<script>
export default {
  name: 'PackageSearch',
  data() {
    return {
      query: this.initialQuery ?? '',
      suggestions: [],
      highlighted: -1,
      open: false,
      expanded: false,
      debounce: null,
      requestId: 0
    };
  },
  mounted() {
    document.addEventListener('mousedown', this.onDocumentMouseDown);
  },
  beforeUnmount() {
    document.removeEventListener('mousedown', this.onDocumentMouseDown);
    clearTimeout(this.debounce);
  },
  methods: {
    toggleSearch() {
      if (this.expanded) {
        this.close();
        return;
      }

      this.expanded = true;
      this.$nextTick(() => this.$refs.input.focus());
    },
    onDocumentMouseDown(event) {
      if (this.expanded && !this.$el.contains(event.target)) this.close();
    },
    onInput() {
      this.highlighted = -1;
      this.open = true;
      clearTimeout(this.debounce);
      const q = this.query;
      this.debounce = setTimeout(() => this.fetchSuggestions(q), 150);
    },
    async fetchSuggestions(q) {
      if (q.trim() === '') {
        this.suggestions = [];
        return;
      }

      // Ignore responses that arrive out of order so the dropdown always
      // reflects the most recent keystroke.
      const id = ++this.requestId;
      try {
        const res = await fetch(`${this.autocompleteUrl}?q=${encodeURIComponent(q)}`);
        if (!res.ok) return;
        const data = await res.json();
        if (id !== this.requestId) return;
        this.suggestions = data;
      } catch (e) {
        // Network hiccups should never break plain Enter-to-search
      }
    },
    move(dir) {
      if (!this.open || this.suggestions.length === 0) return;
      const n = this.suggestions.length;
      this.highlighted = (this.highlighted + dir + n) % n;
    },
    choose(name) {
      this.query = name;
      this.navigate(name);
    },
    submit() {
      const name = this.highlighted >= 0 ? this.suggestions[this.highlighted] : this.query;
      if (name.trim() === '') return;
      this.navigate(name);
    },
    navigate(name) {
      // A bare numeric id is a bot_packages.id (as cited in review notes); jump straight to its report
      // rather than a name search, which would exact-match the digits against a name and find nothing.
      const trimmed = name.trim();
      if (/^\d+$/.test(trimmed)) {
        window.location.href = `/reviews/details/${trimmed}`;
        return;
      }
      window.location.href = `${this.searchUrl}?q=${encodeURIComponent(trimmed)}`;
    },
    onFocus() {
      if (this.suggestions.length > 0) this.open = true;
    },
    onBlur() {
      this.open = false;
    },
    close() {
      this.expanded = false;
      this.open = false;
      this.highlighted = -1;
    },
    dismiss() {
      this.close();
      this.$nextTick(() => this.$refs.trigger.focus());
    }
  }
};
</script>

<style>
.cavil-package-search-control {
  position: relative;
}
.cavil-package-search-trigger {
  color: var(--cavil-fg-secondary);
  white-space: nowrap;
}
.cavil-package-search-trigger:hover,
.cavil-package-search-trigger:focus,
.cavil-package-search-trigger[aria-expanded='true'] {
  color: var(--cavil-fg-emphasis);
}
.cavil-package-search-popover {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(var(--cavil-neutral-rgb), 0.2);
  padding: 0.75rem;
  position: absolute;
  right: 0;
  top: calc(100% + 0.4rem);
  width: min(20rem, calc(100vw - 2rem));
  z-index: 1000;
}
.cavil-package-search-anchor {
  position: relative;
  width: 100%;
}
.cavil-navbar-search .autocomplete-container {
  border-top: 1px solid var(--cavil-border-muted);
  cursor: pointer;
  margin: 0.5rem -0.75rem -0.75rem;
  padding: 0.25rem 0;
}
.cavil-navbar-search .autocomplete {
  max-height: 320px;
  overflow-x: hidden;
  overflow-y: auto;
}
.cavil-navbar-search .autocomplete-item {
  color: var(--cavil-fg);
  font-size: 14px;
  padding: 6px 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cavil-navbar-search .autocomplete-item.active,
.cavil-navbar-search .autocomplete-item:hover {
  background-color: var(--cavil-canvas-subtle);
  color: var(--cavil-fg);
}
@media (max-width: 991.98px) {
  .cavil-package-search-popover {
    left: 0;
    right: auto;
  }
}
</style>
