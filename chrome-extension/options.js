document.addEventListener('DOMContentLoaded', function () {
    chrome.storage.local.get({ url: 'http://localhost:8080/' }, function (data) {
        document.getElementById('url').value = data.url;
    });

    document.getElementById('save').addEventListener('click', function () {
        const url = document.getElementById('url').value.trim();
        if (!url) return;
        chrome.storage.local.set({ url: url }, function () {
            const s = document.getElementById('status');
            s.textContent = 'Saved.';
            setTimeout(function () { s.textContent = ''; }, 2500);
        });
    });
});
