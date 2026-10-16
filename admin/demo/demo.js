/* Debrid Stack Map: a living node network. No external resources. */
var LOGOS = {"synology": "M13.44 8.927l-.889.37.056.117a.623.623 0 0 1 .212-.054c.05 0 .093.017.126.046.033.028.058.081.072.16.015.08.022.29.022.634v2.736c0 .189-.013.316-.042.381a.295.295 0 0 1-.118.142c-.053.031-.147.045-.286.045v.12h1.481v-.12c-.154 0-.261-.017-.32-.048a.29.29 0 0 1-.126-.142c-.026-.06-.04-.187-.04-.378V8.927zm-11.722.34c-.33 0-.608.05-.84.147-.233.1-.411.246-.534.436a1.083 1.083 0 0 0-.185.612c0 .338.131.627.393.864.184.167.507.309.968.422.358.091.587.153.688.191a.7.7 0 0 1 .31.183c.058.07.088.158.088.259 0 .155-.07.291-.21.41-.142.116-.35.176-.628.176-.262 0-.47-.066-.625-.197-.154-.132-.255-.339-.307-.619L0 12.23c.056.48.228.845.517 1.096.289.252.704.378 1.244.378.371 0 .68-.054.93-.156a1.263 1.263 0 0 0 .781-1.169 1.29 1.29 0 0 0-.171-.684 1.203 1.203 0 0 0-.472-.437c-.2-.107-.508-.21-.927-.31-.418-.098-.683-.193-.79-.286a.326.326 0 0 1 .009-.524c.14-.105.336-.156.586-.156.24 0 .422.049.542.145.122.097.199.256.237.471l.864-.028c-.013-.395-.154-.71-.425-.949-.271-.235-.674-.353-1.208-.353zm21.808.33a.475.475 0 1 0-.002.95.475.475 0 0 0 .002-.95zm0 .072a.4.4 0 0 1 .401.403c0 .116-.05.22-.128.294l-.086-.135a.396.396 0 0 0-.065-.078.212.212 0 0 0-.048-.03.2.2 0 0 0 .127-.057.144.144 0 0 0 .043-.109.178.178 0 0 0-.025-.091.125.125 0 0 0-.067-.055.309.309 0 0 0-.123-.02h-.266v.606h.08v-.268h.091c.02 0 .036.001.045.003.013.004.025.007.036.014.013.01.024.023.04.043.015.019.035.049.059.083l.08.125h.043a.396.396 0 0 1-.237.08.405.405 0 0 1-.404-.405c0-.224.18-.403.404-.403zm-.157.191h.191c.044 0 .077.01.097.027a.089.089 0 0 1 .03.07.09.09 0 0 1-.016.055.076.076 0 0 1-.047.035.196.196 0 0 1-.085.013h-.17zm-15.037.6c-.41 0-.752.17-1.023.514v-.455h-.754v3.105h.814v-1.401c0-.348.022-.583.063-.713a.583.583 0 0 1 .234-.306.666.666 0 0 1 .385-.118c.11 0 .208.028.287.082.08.054.135.13.17.229.037.099.054.314.054.646v1.581h.816V11.7a2.54 2.54 0 0 0-.046-.55.925.925 0 0 0-.16-.343.83.83 0 0 0-.341-.25 1.285 1.285 0 0 0-.499-.097zm2.65 0a1.7 1.7 0 0 0-.826.2 1.39 1.39 0 0 0-.571.586 1.684 1.684 0 0 0-.202.793c0 .356.068.657.202.904.134.25.33.438.588.566.259.129.53.194.814.194.46 0 .841-.156 1.144-.463.303-.31.455-.698.455-1.167 0-.465-.15-.85-.451-1.156-.3-.305-.683-.457-1.154-.457zm7.315.05c-.351 0-.64.108-.865.323a1.02 1.02 0 0 0-.336.77c0 .194.05.371.147.534.1.162.24.285.423.379-.223.187-.366.335-.429.44a.55.55 0 0 0-.092.271c0 .068.024.13.071.184.046.056.127.116.24.187a9.626 9.626 0 0 0-.329.355c-.113.145-.19.253-.226.336a.41.41 0 0 0-.034.157c0 .12.081.232.246.343.291.19.649.284 1.071.284.55 0 .996-.16 1.337-.477.232-.216.35-.45.35-.694a.613.613 0 0 0-.183-.45.838.838 0 0 0-.49-.227 8.478 8.478 0 0 0-.878-.053 4.257 4.257 0 0 1-.46-.027c-.105-.015-.177-.04-.212-.075-.038-.037-.056-.072-.056-.112a.37.37 0 0 1 .05-.159.868.868 0 0 1 .186-.221c.156.049.309.07.459.07.36 0 .648-.1.864-.301a.956.956 0 0 0 .323-.722c0-.247-.062-.45-.187-.61h.394c.097 0 .15-.002.167-.01a.056.056 0 0 0 .035-.025.289.289 0 0 0 .018-.12.214.214 0 0 0-.02-.105.083.083 0 0 0-.033-.028.83.83 0 0 0-.166-.008h-.639a1.307 1.307 0 0 0-.746-.21zm-2.752 0c-.252 0-.49.065-.714.194a1.437 1.437 0 0 0-.546.61 1.816 1.816 0 0 0-.205.825c0 .381.114.724.34 1.03a1.29 1.29 0 0 0 1.09.543c.28 0 .532-.07.76-.211.23-.14.409-.35.54-.627.13-.276.194-.55.194-.821 0-.385-.118-.725-.354-1.022a1.344 1.344 0 0 0-1.105-.522zm-12.182.009l1.174 3.113a1.193 1.193 0 0 1-.21.431c-.09.112-.23.167-.419.167-.102 0-.218-.013-.344-.04l.067.645c.152.033.307.052.464.052.155 0 .294-.019.418-.052a1.04 1.04 0 0 0 .31-.138.862.862 0 0 0 .224-.234 2.2 2.2 0 0 0 .205-.414l.199-.545 1.085-2.985h-.844l-.722 2.204-.74-2.204zm16.631.078v.122a.84.84 0 0 1 .245.091c.035.029.08.08.136.157.072.102.125.186.158.255l1.088 2.275-.213.526c-.079.194-.158.326-.236.393-.08.068-.15.104-.217.104a.878.878 0 0 1-.167-.05.924.924 0 0 0-.3-.07c-.105 0-.19.025-.25.084a.286.286 0 0 0-.092.22c0 .098.042.183.126.257a.457.457 0 0 0 .322.112c.18 0 .366-.072.56-.223.193-.15.35-.37.469-.664l1.226-3.014a1.6 1.6 0 0 1 .113-.254.55.55 0 0 1 .145-.146.473.473 0 0 1 .188-.053v-.122h-.978v.122c.093 0 .16.008.197.023a.172.172 0 0 1 .083.057.146.146 0 0 1 .023.087c0 .091-.019.18-.056.271l-.675 1.671-.737-1.53c-.074-.15-.11-.268-.11-.356a.21.21 0 0 1 .074-.16.346.346 0 0 1 .224-.063h.068v-.122zm-1.753.08c.175 0 .316.074.43.217.15.196.224.466.224.815 0 .265-.053.46-.16.584a.516.516 0 0 1-.41.188.528.528 0 0 1-.43-.216c-.149-.19-.223-.458-.223-.802 0-.268.054-.461.163-.59a.515.515 0 0 1 .406-.197zm-2.798.054c.242 0 .44.102.598.312.23.308.346.727.346 1.263 0 .429-.07.73-.209.905a.646.646 0 0 1-.528.264c-.286 0-.516-.161-.691-.477-.174-.32-.263-.695-.263-1.135 0-.272.037-.493.11-.669a.731.731 0 0 1 .285-.361.667.667 0 0 1 .352-.102zm-4.463.395c.216 0 .396.084.543.247.144.162.216.397.216.703 0 .311-.072.55-.216.712a.695.695 0 0 1-.543.248.695.695 0 0 1-.542-.248c-.147-.161-.22-.398-.22-.708 0-.308.073-.545.22-.707a.704.704 0 0 1 .542-.247zm6.66 2.498c.265.036.647.065 1.142.08.34.007.566.034.68.083.113.048.17.13.17.241 0 .157-.094.304-.282.442-.19.138-.48.208-.874.208-.414 0-.732-.07-.951-.204-.128-.078-.19-.168-.19-.277 0-.078.024-.169.076-.26a1.51 1.51 0 0 1 .228-.313z", "plex": "M3.987 8.409c-.96 0-1.587.28-2.12.933v-.72H0v8.88s.038.018.127.037c.138.03.821.187 1.331-.249.441-.377.542-.814.542-1.318v-1.283c.533.573 1.147.813 2 .813 1.84 0 3.253-1.493 3.253-3.48 0-2.12-1.36-3.613-3.266-3.613Zm16.748 5.595.406.591c.391.614.894.906 1.492.908.621-.012 1.064-.562 1.226-.755 0 0-.307-.27-.686-.72-.517-.614-1.214-1.755-1.24-1.803l-1.198 1.779Zm-3.205-1.955c0-2.08-1.52-3.64-3.52-3.64s-3.467 1.587-3.467 3.573a3.48 3.48 0 0 0 3.507 3.52c1.413 0 2.626-.84 3.253-2.293h-2.04l-.093.093c-.427.4-.72.533-1.227.533-.787 0-1.373-.506-1.453-1.266h4.986c.04-.214.054-.307.054-.52Zm-7.671-.219c0 .769.11 1.701.868 2.722l.056.069c-.306.526-.742.88-1.248.88-.399 0-.814-.211-1.138-.579a2.177 2.177 0 0 1-.538-1.441V6.409H9.86l-.001 5.421Zm9.283 3.46h-2.39l2.247-3.332-2.247-3.335h2.39l2.248 3.335-2.248 3.332Zm1.593-1.286Zm-17.162-.342c-.933 0-1.68-.773-1.68-1.72s.76-1.666 1.68-1.666c.92 0 1.68.733 1.68 1.68 0 .946-.733 1.706-1.68 1.706Zm18.361-1.974L24 8.622h-2.391l-.87 1.293 1.195 1.773Zm-9.404-.466c.16-.706.72-1.133 1.493-1.133.773 0 1.373.467 1.507 1.133h-3Z", "docker": "M13.983 11.078h2.119a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186h-2.119a.185.185 0 00-.185.185v1.888c0 .102.083.185.185.185m-2.954-5.43h2.118a.186.186 0 00.186-.186V3.574a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m0 2.716h2.118a.187.187 0 00.186-.186V6.29a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.185.185v1.887c0 .102.082.185.185.186m-2.93 0h2.12a.186.186 0 00.184-.186V6.29a.185.185 0 00-.185-.185H8.1a.185.185 0 00-.185.185v1.887c0 .102.083.185.185.186m-2.964 0h2.119a.186.186 0 00.185-.186V6.29a.185.185 0 00-.185-.185H5.136a.186.186 0 00-.186.185v1.887c0 .102.084.185.186.186m5.893 2.715h2.118a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m-2.93 0h2.12a.185.185 0 00.184-.185V9.006a.185.185 0 00-.184-.186h-2.12a.185.185 0 00-.184.185v1.888c0 .102.083.185.185.185m-2.964 0h2.119a.185.185 0 00.185-.185V9.006a.185.185 0 00-.184-.186h-2.12a.186.186 0 00-.186.186v1.887c0 .102.084.185.186.185m-2.92 0h2.12a.185.185 0 00.184-.185V9.006a.185.185 0 00-.184-.186h-2.12a.185.185 0 00-.184.185v1.888c0 .102.082.185.185.185M23.763 9.89c-.065-.051-.672-.51-1.954-.51-.338.001-.676.03-1.01.087-.248-1.7-1.653-2.53-1.716-2.566l-.344-.199-.226.327c-.284.438-.49.922-.612 1.43-.23.97-.09 1.882.403 2.661-.595.332-1.55.413-1.744.42H.751a.751.751 0 00-.75.748 11.376 11.376 0 00.692 4.062c.545 1.428 1.355 2.48 2.41 3.124 1.18.723 3.1 1.137 5.275 1.137.983.003 1.963-.086 2.93-.266a12.248 12.248 0 003.823-1.389c.98-.567 1.86-1.288 2.61-2.136 1.252-1.418 1.998-2.997 2.553-4.4h.221c1.372 0 2.215-.549 2.68-1.009.309-.293.55-.65.707-1.046l.098-.288Z", "rclone": "M11.842.6258C9.3647.6813 6.9754 1.9906 5.646 4.2933c-.7593 1.3144-1.0647 2.7662-.966 4.1745a7.99 7.99 0 0 1 2.6568-.4541l1.4705-.0013c-.0093-.5594.1245-1.1284.4245-1.6482.8827-1.5284 2.837-2.0522 4.3654-1.1695 1.5284.8824 2.0519 2.8366 1.1695 4.365l-1.4782 2.5647 1.1955 2.0714 2.3914-.0004 1.4775-2.5655c2.0262-3.5088.8239-7.9959-2.6853-10.0217C14.4614.9118 13.1396.5967 11.842.6258m-1.5451 8.073-2.9605.0029C3.2844 8.7017 0 11.9867 0 16.0383c0 4.052 3.2844 7.3367 7.3364 7.3367 1.5174 0 2.9267-.4609 4.0967-1.2497a8 8 0 0 1-1.72-2.0748l-.7368-1.273c-.4799.288-1.0392.4565-1.6395.4565-1.765 0-3.1958-1.4307-3.1958-3.1958 0-1.7647 1.4307-3.1954 3.1958-3.1954l2.96-.0022 1.1962-2.0708zm9.587.7475a7.99 7.99 0 0 1-.935 2.5278l-.7344 1.2745c.4892.2717.915.6719 1.2153 1.192.8823 1.528.3585 3.4826-1.1699 4.365-1.528.8823-3.4828.3588-4.3651-1.1696l-1.482-2.5628h-2.3915L8.8256 17.144l1.483 2.5626c2.0262 3.5091 6.513 4.7112 10.022 2.685 3.5089-2.0257 4.7112-6.5125 2.6853-10.0216-.7588-1.3144-1.863-2.3052-3.132-2.9237", "android": "M18.4395 5.5586c-.675 1.1664-1.352 2.3318-2.0274 3.498-.0366-.0155-.0742-.0286-.1113-.043-1.8249-.6957-3.484-.8-4.42-.787-1.8551.0185-3.3544.4643-4.2597.8203-.084-.1494-1.7526-3.021-2.0215-3.4864a1.1451 1.1451 0 0 0-.1406-.1914c-.3312-.364-.9054-.4859-1.379-.203-.475.282-.7136.9361-.3886 1.5019 1.9466 3.3696-.0966-.2158 1.9473 3.3593.0172.031-.4946.2642-1.3926 1.0177C2.8987 12.176.452 14.772 0 18.9902h24c-.119-1.1108-.3686-2.099-.7461-3.0683-.7438-1.9118-1.8435-3.2928-2.7402-4.1836a12.1048 12.1048 0 0 0-2.1309-1.6875c.6594-1.122 1.312-2.2559 1.9649-3.3848.2077-.3615.1886-.7956-.0079-1.1191a1.1001 1.1001 0 0 0-.8515-.5332c-.5225-.0536-.9392.3128-1.0488.5449zm-.0391 8.461c.3944.5926.324 1.3306-.1563 1.6503-.4799.3197-1.188.0985-1.582-.4941-.3944-.5927-.324-1.3307.1563-1.6504.4727-.315 1.1812-.1086 1.582.4941zM7.207 13.5273c.4803.3197.5506 1.0577.1563 1.6504-.394.5926-1.1038.8138-1.584.4941-.48-.3197-.5503-1.0577-.1563-1.6504.4008-.6021 1.1087-.8106 1.584-.4941z", "apple": "M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"};
(function () {
  "use strict";
  var NS = "http://www.w3.org/2000/svg";
  var svg = document.getElementById("net");
  var reduce = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;

  function el(tag, attrs, parent) {
    var n = document.createElementNS(NS, tag);
    for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }
  function fitLogo(name, size, color, parent, x, y, align) {
    var s = el("svg", { x: x, y: y, width: size[0], height: size[1], viewBox: "0 0 24 24", preserveAspectRatio: (align || "xMidYMid") + " meet" }, parent);
    var p = el("path", { d: LOGOS[name], style: "fill:" + color }, s);
    try { var b = p.getBBox(); if (b.width && b.height) s.setAttribute("viewBox", b.x + " " + b.y + " " + b.width + " " + b.height); } catch (e) {}
    return s;
  }

  // Lucide-style icons (ISC)
  var ICONS = {
    cloud: '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/>',
    router: '<rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6.01 18H6M10.01 18H10M15 10v4M17.84 7.17a4 4 0 0 0-5.66 0M20.66 4.34a8 8 0 0 0-11.31 0"/>',
    tree: '<path d="M20 10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1h-2.5a1 1 0 0 1-.8-.4l-.9-1.2A1 1 0 0 0 15 3h-2a1 1 0 0 0-1 1v5a1 1 0 0 0 1 1Z"/><path d="M20 21a1 1 0 0 0 1-1v-3a1 1 0 0 0-1-1h-2.9a1 1 0 0 1-.88-.55l-.42-.85a1 1 0 0 0-.92-.6H13a1 1 0 0 0-1 1v5a1 1 0 0 0 1 1Z"/><path d="M3 5a2 2 0 0 0 2 2h3"/><path d="M3 3v13a2 2 0 0 0 2 2h3"/>',
    database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5"/><path d="M3 12a9 3 0 0 0 18 0"/>',
    dashboard: '<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
    shield: '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
    activity: '<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>',
    laptop: '<path d="M20 16V7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v9m16 0H4m16 0 1.28 2.55a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45L4 16"/>'
  };

  // Nodes: position, size, network colour, glyph, labels
  var NODES = {
    rd:       { x: 112, y: 150, r: 30, net: "egress",   icon: "cloud",     label: "Real-Debrid", sub: "cloud library", tip: "Real-Debrid holds your library. Nothing is stored on the NAS." },
    plextv:   { x: 112, y: 410, r: 24, net: "plex",     logo: "plex",      label: "plex.tv",     sub: "sign-in · info", tip: "plex.tv: sign-in, posters and descriptions. Plex reaches out; nothing reaches in." },
    router:   { x: 218, y: 280, r: 24, net: "egress",   icon: "router",    label: "Router",      sub: "UPnP off", tip: "Router: no port forwards and UPnP off, so nothing can open a way in." },
    zurg:     { x: 340, y: 150, r: 30, net: "egress",   icon: "tree",      label: "Zurg",        sub: "127.0.0.1:9999", ring: true, tip: "Zurg turns your Real-Debrid library into folders over WebDAV. Listens on the NAS only." },
    rclone:   { x: 490, y: 150, r: 28, net: "rclone",   logo: "rclone",    label: "rclone",      sub: "no internet", ring: true, tip: "rclone mounts Zurg as a read-only folder with a read cache. No internet, no open ports." },
    mount:    { x: 640, y: 150, r: 27, net: "lan",      icon: "database",  label: "/mnt/zurg",   sub: "read-only", tip: "The library mount: looks like a local disk, streamed on demand. Read-only for everything." },
    plex:     { x: 640, y: 300, r: 36, net: "plex",     logo: "plex",      label: "Plex",        sub: ":32400", ring: true, tip: "Plex reads the library read-only and streams to your devices. Remote access, relay and UPnP are off." },
    admin:    { x: 640, y: 440, r: 26, net: "admin",    icon: "dashboard", label: "Manage page", sub: "https · login", tip: "The management page runs as nobody without Docker access; it can only queue requests." },
    agent:    { x: 490, y: 440, r: 23, net: "admin",    icon: "shield",    label: "Host agent",  sub: "root · checks", tip: "The host agent checks every request against a fixed list before applying it." },
    watchdog: { x: 340, y: 440, r: 23, net: "internal", icon: "activity",  label: "Watchdog",    sub: "every minute", beat: true, tip: "The watchdog heals a dropped mount, re-applies the firewall and runs the agent, every minute." },
    tv:       { x: 885, y: 150, r: 28, net: "android",  logo: "android",   label: "Android TV",  sub: "Plex app", tip: "The Plex app on Android TV plays straight from the NAS." },
    phone:    { x: 885, y: 300, r: 26, net: "apple",    logo: "apple",     label: "iPhone",      sub: "Plex app", tip: "Works on your home Wi-Fi; away from home it can't reach Plex, on purpose." },
    laptop:   { x: 885, y: 440, r: 26, net: "lan",      icon: "laptop",    label: "Laptop",      sub: "browser", tip: "Plex in the browser, and the management page over HTTPS." }
  };

  // Edges: from, to, wire colour, comets per cycle, seconds per trip, label, bend, style
  var EDGES = [
    { a: "rd", b: "router", net: "egress", n: 2, dur: 1.8, bend: 18 },
    { a: "router", b: "zurg", net: "egress", n: 2, dur: 1.8, bend: -22, chip: "HTTPS", chipAt: .38 },
    { a: "zurg", b: "rclone", net: "internal", n: 2, dur: 1.2, bend: 0, chip: "WebDAV" },
    { a: "rclone", b: "mount", net: "internal", n: 2, dur: 1.1, bend: 0, chip: "FUSE" },
    { a: "mount", b: "plex", net: "lan", n: 2, dur: 1.2, bend: 0, chip: "read-only" },
    { a: "plex", b: "tv", net: "lan", n: 2, dur: 1.9, bend: -26, chip: ":32400" },
    { a: "plex", b: "phone", net: "lan", n: 1, dur: 1.7, bend: 0 },
    { a: "plex", b: "laptop", net: "lan", n: 1, dur: 2.0, bend: 26 },
    { a: "laptop", b: "admin", net: "admin", n: 1, dur: 1.7, bend: 0, chip: ":8099" },
    { a: "admin", b: "agent", net: "admin", n: 1, dur: 1.5, bend: 0, dash: true, chip: "requests" },
    { a: "watchdog", b: "agent", net: "internal", n: 1, dur: 2.2, bend: 0, dash: true },
    { a: "plex", b: "router", net: "egress", n: 1, dur: 4.2, bend: -70, dash: true, small: true },
    { a: "router", b: "plextv", net: "egress", n: 1, dur: 2.0, bend: -16, dash: true, small: true, chip: "metadata · out", chipAt: .68 }
  ];

  var C = function (net) { return "var(--" + net + ")"; };

  // NAS heading: Synology wordmark · Docker whale
  var head = document.getElementById("nas-head");
  fitLogo("synology", [72, 15], "var(--ink)", head, 284, 60, "xMinYMid");
  el("text", { class: "zlabel", x: 364, y: 72 }, head).textContent = "NAS ·";
  fitLogo("docker", [19, 16], "var(--docker)", head, 402, 59);
  el("text", { class: "zlabel", x: 427, y: 72 }, head).textContent = "DOCKER";

  // ------------------------------------------------------------ nodes
  var nodesG = document.getElementById("nodes");
  Object.keys(NODES).forEach(function (id, i) {
    var n = NODES[id];
    n.phase = i * 1.37; n.cx = n.x; n.cy = n.y;
    var g = el("g", { class: "node" }, nodesG);
    el("title", {}, g).textContent = n.label + ": " + n.tip;
    var halo = el("circle", { class: "halo", r: n.r + 14, style: "fill:" + C(n.net) + ";fill-opacity:.14;filter:url(#soft);animation-delay:-" + (i * 0.6).toFixed(1) + "s" }, g);
    if (n.ring) el("circle", { class: "ring", r: n.r + 8, style: "stroke:" + C(n.net) + ";stroke-opacity:.55;animation-duration:" + (14 + i) + "s" }, g);
    el("circle", { class: "ping", r: n.r, style: "stroke:" + C(n.net) }, g);
    var core = el("circle", { class: "core" + (n.beat ? " beat" : ""), r: n.r, fill: "url(#coreg)", style: "stroke:" + C(n.net) + ";stroke-opacity:.7" }, g);
    var s = Math.round(n.r * 0.95);
    if (n.logo) fitLogo(n.logo, n.logo === "plex" ? [s * 1.25, s * 0.6] : [s, s], C(n.net), g, -(n.logo === "plex" ? s * 0.625 : s / 2), -(n.logo === "plex" ? s * 0.3 : s / 2));
    else {
      var ic = el("svg", { x: -s / 2, y: -s / 2, width: s, height: s, viewBox: "0 0 24 24" }, g);
      el("g", { class: "icon", style: "stroke:" + C(n.net) }, ic).innerHTML = ICONS[n.icon];
    }
    el("text", { class: "label", y: n.r + 17 }, g).textContent = n.label;
    el("text", { class: "sub", y: n.r + 30 }, g).textContent = n.sub;
    // satellites orbiting the busiest nodes
    n.sats = [];
    if (n.ring) for (var k = 0; k < 3; k++) n.sats.push(el("circle", { r: 2.4, style: "fill:" + C(n.net) + ";opacity:.85" }, g));
    n.g = g; n.halo = halo; n.core = core;
  });

  // ------------------------------------------------------------ edges + comets
  var edgesG = document.getElementById("edges"), chipsG = document.getElementById("chips"), cometsG = document.getElementById("comets");
  EDGES.forEach(function (e, i) {
    e.bg = el("path", { class: "edge bg" }, edgesG);
    e.line = el("path", { class: "edge" + (e.dash ? " dash" : ""), style: "stroke:" + C(e.net) + ";stroke-width:" + (e.small ? 2 : 2.6) + ";opacity:.6" }, edgesG);
    if (e.chip) {
      e.chipG = el("g", { class: "chip", style: "fill:" + C(e.net) }, chipsG);
      e.chipR = el("rect", { height: 16, rx: 8 }, e.chipG);
      e.chipT = el("text", { "text-anchor": "middle" }, e.chipG);
      e.chipT.textContent = e.chip;
      e.chipW = e.chip.length * 5.9 + 14;
      e.chipR.setAttribute("width", e.chipW);
    }
    e.comets = [];
    for (var c = 0; c < e.n; c++) {
      var parts = [[4.4, 1], [3.4, .55], [2.6, .32], [1.9, .16]].map(function (p) {
        return el("circle", { class: "comet", r: p[0] * (e.small ? .7 : 1), style: "fill:" + C(e.net) + ";opacity:" + p[1] }, cometsG);
      });
      e.comets.push({ t: c / e.n, parts: parts });
    }
  });

  // blocked attempt from the internet, dying at the router
  var blockLine = el("path", { class: "edge dash", d: "M24 280 C80 280 140 280 188 280", style: "stroke:var(--danger);stroke-width:2;opacity:.75" }, edgesG);
  var blockHead = el("circle", { class: "comet", r: 4, style: "fill:var(--danger)" }, cometsG);
  var flash = el("circle", { cx: 194, cy: 280, r: 10, style: "fill:var(--danger);opacity:0" }, cometsG);
  var xm = el("g", { class: "xmark" }, cometsG);
  el("line", { x1: 186, y1: 272, x2: 200, y2: 286 }, xm); el("line", { x1: 200, y1: 272, x2: 186, y2: 286 }, xm);
  el("text", { class: "note", x: 26, y: 266 }, edgesG).textContent = "nothing comes in";
  void blockLine;

  // ------------------------------------------------------------ geometry
  function geom(e) {
    var A = NODES[e.a], B = NODES[e.b];
    var dx = B.cx - A.cx, dy = B.cy - A.cy, len = Math.hypot(dx, dy) || 1;
    var ux = dx / len, uy = dy / len;
    var p0 = [A.cx + ux * (A.r + 4), A.cy + uy * (A.r + 4)];
    var p2 = [B.cx - ux * (B.r + 4), B.cy - uy * (B.r + 4)];
    var mx = (p0[0] + p2[0]) / 2, my = (p0[1] + p2[1]) / 2;
    var p1 = [mx - uy * e.bend, my + ux * e.bend];
    return [p0, p1, p2];
  }
  function at(g, t) {
    var u = 1 - t;
    return [u * u * g[0][0] + 2 * u * t * g[1][0] + t * t * g[2][0], u * u * g[0][1] + 2 * u * t * g[1][1] + t * t * g[2][1]];
  }
  function hit(id) {
    var n = NODES[id];
    if (!n || n.hitting) return;
    n.hitting = true;
    n.g.classList.add("hit");
    setTimeout(function () { n.g.classList.remove("hit"); n.hitting = false; }, 900);
  }

  // ------------------------------------------------------------ frame loop
  var last = performance.now(), blockT = 0;
  function frame(now) {
    var dt = Math.max(0, Math.min(0.05, (now - last) / 1000));
    last = now;
    var t = now / 1000;
    // gentle drift: every node floats on its own slow path
    Object.keys(NODES).forEach(function (id) {
      var n = NODES[id];
      var amp = reduce ? 0 : 3.2;
      n.cx = n.x + Math.sin(t * 0.55 + n.phase) * amp;
      n.cy = n.y + Math.cos(t * 0.43 + n.phase * 1.3) * amp;
      n.g.setAttribute("transform", "translate(" + n.cx.toFixed(2) + "," + n.cy.toFixed(2) + ")");
      n.sats.forEach(function (s, k) {
        var a = (reduce ? 0 : t * (0.9 + k * 0.15)) + k * 2.094;
        s.setAttribute("cx", (Math.cos(a) * (n.r + 8)).toFixed(2));
        s.setAttribute("cy", (Math.sin(a) * (n.r + 8)).toFixed(2));
      });
    });
    EDGES.forEach(function (e) {
      var g = geom(e);
      var d = "M" + g[0][0].toFixed(1) + " " + g[0][1].toFixed(1) + " Q" + g[1][0].toFixed(1) + " " + g[1][1].toFixed(1) + " " + g[2][0].toFixed(1) + " " + g[2][1].toFixed(1);
      e.bg.setAttribute("d", d); e.line.setAttribute("d", d);
      if (e.chipG) {
        var m = at(g, e.chipAt || 0.5);
        var vertical = Math.abs(g[2][0] - g[0][0]) < 20;
        // beside a vertical wire, above any other wire
        var cx = vertical ? m[0] + 10 : m[0] - e.chipW / 2, cy = vertical ? m[1] - 8 : m[1] - 22;
        e.chipG.setAttribute("transform", "translate(" + cx.toFixed(1) + "," + cy.toFixed(1) + ")");
        e.chipT.setAttribute("x", e.chipW / 2); e.chipT.setAttribute("y", 11.5);
      }
      e.comets.forEach(function (c) {
        if (!reduce) {
          c.t += dt / e.dur;
          if (c.t >= 1) { c.t -= 1; hit(e.b); }
        }
        c.parts.forEach(function (p, k) {
          var tt = Math.max(0, c.t - k * 0.035);
          var q = at(g, tt);
          p.setAttribute("cx", q[0].toFixed(1)); p.setAttribute("cy", q[1].toFixed(1));
          p.style.visibility = reduce ? "hidden" : "visible";
        });
      });
    });
    // blocked packet: travels, flashes at the cross, starts again
    if (!reduce) {
      blockT += dt / 2.4;
      if (blockT >= 1) blockT = 0;
      var bt = Math.min(1, blockT / 0.7);
      blockHead.setAttribute("cx", (24 + bt * 162).toFixed(1)); blockHead.setAttribute("cy", 280);
      blockHead.style.opacity = blockT < 0.7 ? 1 : 0;
      var f = blockT > 0.7 ? (blockT - 0.7) / 0.3 : 0;
      flash.setAttribute("r", (10 + f * 18).toFixed(1));
      flash.style.opacity = blockT > 0.7 ? (0.8 * (1 - f)).toFixed(2) : 0;
    } else { blockHead.style.opacity = 0; }
    if (!reduce) requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
