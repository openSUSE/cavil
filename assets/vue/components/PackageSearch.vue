<template>
  <form class="d-flex cavil-navbar-search" role="search" @submit.prevent="submit">
    <div class="cavil-package-search-anchor">
      <input
        ref="input"
        v-model="query"
        type="text"
        class="form-control cavil-search-input"
        placeholder="Search packages"
        aria-label="Search packages"
        autocomplete="off"
        @input="onInput"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="submit"
        @keydown.esc="close"
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
      debounce: null,
      requestId: 0
    };
  },
  methods: {
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
      window.location.href = `${this.searchUrl}?q=${encodeURIComponent(name)}`;
    },
    onFocus() {
      if (this.suggestions.length > 0) this.open = true;
    },
    onBlur() {
      this.open = false;
    },
    close() {
      this.open = false;
      this.highlighted = -1;
    }
  }
};
</script>

<style>
.cavil-package-search-anchor {
  position: relative;
  width: 100%;
}
.cavil-navbar-search .autocomplete-container {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  cursor: pointer;
  left: 0;
  margin: 4px 0 0;
  padding: 4px 0;
  position: absolute;
  right: 0;
  z-index: 1000;
}
.cavil-navbar-search .autocomplete {
  max-height: 320px;
  overflow-x: hidden;
  overflow-y: auto;
}
.cavil-navbar-search .autocomplete-item {
  color: #1f2328;
  font-size: 14px;
  padding: 6px 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cavil-navbar-search .autocomplete-item.active,
.cavil-navbar-search .autocomplete-item:hover {
  background-color: #f6f8fa;
  color: #1f2328;
}
</style>
