import UserAgent from '@mojojs/user-agent';

export default {
  data() {
    return {
      params: {},
      refreshDelay: 15000,
      refreshTimer: null
    };
  },
  mounted() {
    this.doApiRefresh();
    this.refreshTimer = setInterval(this.doApiRefresh, this.refreshDelay);
  },
  unmounted() {
    this.cancelApiRefresh();
  },
  methods: {
    async doApiRefresh() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.refreshUrl, {query: this.params});
      const data = await res.json();
      this.$emit('last-updated', data.last_updated);
      this.refreshData(data);
    },
    cancelApiRefresh() {
      clearInterval(this.refreshTimer);
    }
  }
};
