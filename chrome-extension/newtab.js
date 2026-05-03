document.addEventListener('DOMContentLoaded', function () {
    chrome.storage.local.get({ url: 'http://localhost:8080/' }, function (data) {
        window.location.replace(data.url);
    });
});
