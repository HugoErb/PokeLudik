-- ============================================================================
-- Size It Up : estimer la taille d'un Pokémon par rapport à un autre (solo + duo).
-- Idempotente : peut être rejouée sans erreur.
-- ============================================================================

-- ── Tailles dans le catalogue (mètres, comme src/assets/pokemon.json) ────────
ALTER TABLE public.pokemon_catalog ADD COLUMN IF NOT EXISTS height numeric(5,2);

UPDATE public.pokemon_catalog pc SET height = v.height
FROM (VALUES
(1,0.7),
(2,1),
(3,2),
(4,0.6),
(5,1.1),
(6,1.7),
(7,0.5),
(8,1),
(9,1.6),
(10,0.3),
(11,0.7),
(12,1.1),
(13,0.3),
(14,0.6),
(15,1),
(16,0.3),
(17,1.1),
(18,1.5),
(19,0.3),
(20,0.7),
(21,0.3),
(22,1.2),
(23,2),
(24,3.5),
(25,0.4),
(26,0.8),
(27,0.6),
(28,1),
(29,0.4),
(30,0.8),
(31,1.3),
(32,0.5),
(33,0.9),
(34,1.4),
(35,0.6),
(36,1.3),
(37,0.6),
(38,1.1),
(39,0.5),
(40,1),
(41,0.8),
(42,1.6),
(43,0.5),
(44,0.8),
(45,1.2),
(46,0.3),
(47,1),
(48,1),
(49,1.5),
(50,0.2),
(51,0.7),
(52,0.4),
(53,1),
(54,0.8),
(55,1.7),
(56,0.5),
(57,1),
(58,0.7),
(59,1.9),
(60,0.6),
(61,1),
(62,1.3),
(63,0.9),
(64,1.3),
(65,1.5),
(66,0.8),
(67,1.5),
(68,1.6),
(69,0.7),
(70,1),
(71,1.7),
(72,0.9),
(73,1.6),
(74,0.4),
(75,1),
(76,1.4),
(77,1),
(78,1.7),
(79,1.2),
(80,1.6),
(81,0.3),
(82,1),
(83,0.8),
(84,1.4),
(85,1.8),
(86,1.1),
(87,1.7),
(88,0.9),
(89,1.2),
(90,0.3),
(91,1.5),
(92,1.3),
(93,1.6),
(94,1.5),
(95,8.8),
(96,1),
(97,1.6),
(98,0.4),
(99,1.3),
(100,0.5),
(101,1.2),
(102,0.4),
(103,2),
(104,0.4),
(105,1),
(106,1.5),
(107,1.4),
(108,1.2),
(109,0.6),
(110,1.2),
(111,1),
(112,1.9),
(113,1.1),
(114,1),
(115,2.2),
(116,0.4),
(117,1.2),
(118,0.6),
(119,1.3),
(120,0.8),
(121,1.1),
(122,1.3),
(123,1.5),
(124,1.4),
(125,1.1),
(126,1.3),
(127,1.5),
(128,1.4),
(129,0.9),
(130,6.5),
(131,2.5),
(132,0.3),
(133,0.3),
(134,1),
(135,0.8),
(136,0.9),
(137,0.8),
(138,0.4),
(139,1),
(140,0.5),
(141,1.3),
(142,1.8),
(143,2.1),
(144,1.7),
(145,1.6),
(146,2),
(147,1.8),
(148,4),
(149,2.2),
(150,2),
(151,0.4),
(152,0.9),
(153,1.2),
(154,1.8),
(155,0.5),
(156,0.9),
(157,1.7),
(158,0.6),
(159,1.1),
(160,2.3),
(161,0.8),
(162,1.8),
(163,0.7),
(164,1.6),
(165,1),
(166,1.4),
(167,0.5),
(168,1.1),
(169,1.8),
(170,0.5),
(171,1.2),
(172,0.3),
(173,0.3),
(174,0.3),
(175,0.3),
(176,0.6),
(177,0.2),
(178,1.5),
(179,0.6),
(180,0.8),
(181,1.4),
(182,0.4),
(183,0.4),
(184,0.8),
(185,1.2),
(186,1.1),
(187,0.4),
(188,0.6),
(189,0.8),
(190,0.8),
(191,0.3),
(192,0.8),
(193,1.2),
(194,0.4),
(195,1.4),
(196,0.9),
(197,1),
(198,0.5),
(199,2),
(200,0.7),
(201,0.5),
(202,1.3),
(203,1.5),
(204,0.6),
(205,1.2),
(206,1.5),
(207,1.1),
(208,9.2),
(209,0.6),
(210,1.4),
(211,0.5),
(212,1.8),
(213,0.6),
(214,1.5),
(215,0.9),
(216,0.6),
(217,1.8),
(218,0.7),
(219,0.8),
(220,0.4),
(221,1.1),
(222,0.6),
(223,0.6),
(224,0.9),
(225,0.9),
(226,2.1),
(227,1.7),
(228,0.6),
(229,1.4),
(230,1.8),
(231,0.5),
(232,1.1),
(233,0.6),
(234,1.4),
(235,1.2),
(236,0.7),
(237,1.4),
(238,0.4),
(239,0.6),
(240,0.7),
(241,1.2),
(242,1.5),
(243,1.9),
(244,2.1),
(245,2),
(246,0.6),
(247,1.2),
(248,2),
(249,5.2),
(250,3.8),
(251,0.6),
(252,0.5),
(253,0.9),
(254,1.7),
(255,0.4),
(256,0.9),
(257,1.9),
(258,0.4),
(259,0.7),
(260,1.5),
(261,0.5),
(262,1),
(263,0.4),
(264,0.5),
(265,0.3),
(266,0.6),
(267,1),
(268,0.7),
(269,1.2),
(270,0.5),
(271,1.2),
(272,1.5),
(273,0.5),
(274,1),
(275,1.3),
(276,0.3),
(277,0.7),
(278,0.6),
(279,1.2),
(280,0.4),
(281,0.8),
(282,1.6),
(283,0.5),
(284,0.8),
(285,0.4),
(286,1.2),
(287,0.8),
(288,1.4),
(289,2),
(290,0.5),
(291,0.8),
(292,0.8),
(293,0.6),
(294,1),
(295,1.5),
(296,1),
(297,2.3),
(298,0.2),
(299,1),
(300,0.6),
(301,1.1),
(302,0.5),
(303,0.6),
(304,0.4),
(305,0.9),
(306,2.1),
(307,0.6),
(308,1.3),
(309,0.6),
(310,1.5),
(311,0.4),
(312,0.4),
(313,0.7),
(314,0.6),
(315,0.3),
(316,0.4),
(317,1.7),
(318,0.8),
(319,1.8),
(320,2),
(321,14.5),
(322,0.7),
(323,1.9),
(324,0.5),
(325,0.7),
(326,0.9),
(327,1.1),
(328,0.7),
(329,1.1),
(330,2),
(331,0.4),
(332,1.3),
(333,0.4),
(334,1.1),
(335,1.3),
(336,2.7),
(337,1),
(338,1.2),
(339,0.4),
(340,0.9),
(341,0.6),
(342,1.1),
(343,0.5),
(344,1.5),
(345,1),
(346,1.5),
(347,0.7),
(348,1.5),
(349,0.6),
(350,6.2),
(351,0.3),
(352,1),
(353,0.6),
(354,1.1),
(355,0.8),
(356,1.6),
(357,2),
(358,0.6),
(359,1.2),
(360,0.6),
(361,0.7),
(362,1.5),
(363,0.8),
(364,1.1),
(365,1.4),
(366,0.4),
(367,1.7),
(368,1.8),
(369,1),
(370,0.6),
(371,0.6),
(372,1.1),
(373,1.5),
(374,0.6),
(375,1.2),
(376,1.6),
(377,1.7),
(378,1.8),
(379,1.9),
(380,1.4),
(381,2),
(382,4.5),
(383,3.5),
(384,7),
(385,0.3),
(386,1.7),
(387,0.4),
(388,1.1),
(389,2.2),
(390,0.5),
(391,0.9),
(392,1.2),
(393,0.4),
(394,0.8),
(395,1.7),
(396,0.3),
(397,0.6),
(398,1.2),
(399,0.5),
(400,1),
(401,0.3),
(402,1),
(403,0.5),
(404,0.9),
(405,1.4),
(406,0.2),
(407,0.9),
(408,0.9),
(409,1.6),
(410,0.5),
(411,1.3),
(412,0.2),
(413,0.5),
(414,0.9),
(415,0.3),
(416,1.2),
(417,0.4),
(418,0.7),
(419,1.1),
(420,0.4),
(421,0.5),
(422,0.3),
(423,0.9),
(424,1.2),
(425,0.4),
(426,1.2),
(427,0.4),
(428,1.2),
(429,0.9),
(430,0.9),
(431,0.5),
(432,1),
(433,0.2),
(434,0.4),
(435,1),
(436,0.5),
(437,1.3),
(438,0.5),
(439,0.6),
(440,0.6),
(441,0.5),
(442,1),
(443,0.7),
(444,1.4),
(445,1.9),
(446,0.6),
(447,0.7),
(448,1.2),
(449,0.8),
(450,2),
(451,0.8),
(452,1.3),
(453,0.7),
(454,1.3),
(455,1.4),
(456,0.4),
(457,1.2),
(458,1),
(459,1),
(460,2.2),
(461,1.1),
(462,1.2),
(463,1.7),
(464,2.4),
(465,2),
(466,1.8),
(467,1.6),
(468,1.5),
(469,1.9),
(470,1),
(471,0.8),
(472,2),
(473,2.5),
(474,0.9),
(475,1.6),
(476,1.4),
(477,2.2),
(478,1.3),
(479,0.3),
(480,0.3),
(481,0.3),
(482,0.3),
(483,5.4),
(484,4.2),
(485,1.7),
(486,3.7),
(487,4.5),
(488,1.5),
(489,0.4),
(490,0.3),
(491,1.5),
(492,0.2),
(493,3.2),
(494,0.4),
(495,0.6),
(496,0.8),
(497,3.3),
(498,0.5),
(499,1),
(500,1.6),
(501,0.5),
(502,0.8),
(503,1.5),
(504,0.5),
(505,1.1),
(506,0.4),
(507,0.9),
(508,1.2),
(509,0.4),
(510,1.1),
(511,0.6),
(512,1.1),
(513,0.6),
(514,1),
(515,0.6),
(516,1),
(517,0.6),
(518,1.1),
(519,0.3),
(520,0.6),
(521,1.2),
(522,0.8),
(523,1.6),
(524,0.4),
(525,0.9),
(526,1.7),
(527,0.4),
(528,0.9),
(529,0.3),
(530,0.7),
(531,1.1),
(532,0.6),
(533,1.2),
(534,1.4),
(535,0.5),
(536,0.8),
(537,1.5),
(538,1.3),
(539,1.4),
(540,0.3),
(541,0.5),
(542,1.2),
(543,0.4),
(544,1.2),
(545,2.5),
(546,0.3),
(547,0.7),
(548,0.5),
(549,1.1),
(550,1),
(551,0.7),
(552,1),
(553,1.5),
(554,0.6),
(555,1.3),
(556,1),
(557,0.3),
(558,1.4),
(559,0.6),
(560,1.1),
(561,1.4),
(562,0.5),
(563,1.7),
(564,0.7),
(565,1.2),
(566,0.5),
(567,1.4),
(568,0.6),
(569,1.9),
(570,0.7),
(571,1.6),
(572,0.4),
(573,0.5),
(574,0.4),
(575,0.7),
(576,1.5),
(577,0.3),
(578,0.6),
(579,1),
(580,0.5),
(581,1.3),
(582,0.4),
(583,1.1),
(584,1.3),
(585,0.6),
(586,1.9),
(587,0.4),
(588,0.5),
(589,1),
(590,0.2),
(591,0.6),
(592,1.2),
(593,2.2),
(594,1.2),
(595,0.1),
(596,0.8),
(597,0.6),
(598,1),
(599,0.3),
(600,0.6),
(601,0.6),
(602,0.2),
(603,1.2),
(604,2.1),
(605,0.5),
(606,1),
(607,0.3),
(608,0.6),
(609,1),
(610,0.6),
(611,1),
(612,1.8),
(613,0.5),
(614,2.6),
(615,1.1),
(616,0.4),
(617,0.8),
(618,0.7),
(619,0.9),
(620,1.4),
(621,1.6),
(622,1),
(623,2.8),
(624,0.5),
(625,1.6),
(626,1.6),
(627,0.5),
(628,1.5),
(629,0.5),
(630,1.2),
(631,1.4),
(632,0.3),
(633,0.8),
(634,1.4),
(635,1.8),
(636,1.1),
(637,1.6),
(638,2.1),
(639,1.9),
(640,2),
(641,1.5),
(642,1.5),
(643,3.2),
(644,2.9),
(645,1.5),
(646,3),
(647,1.4),
(648,0.6),
(649,1.5),
(650,0.4),
(651,0.7),
(652,1.6),
(653,0.4),
(654,1),
(655,1.5),
(656,0.3),
(657,0.6),
(658,1.5),
(659,0.4),
(660,1),
(661,0.3),
(662,0.7),
(663,1.2),
(664,0.3),
(665,0.3),
(666,1.2),
(667,0.6),
(668,1.5),
(669,0.1),
(670,0.2),
(671,1.1),
(672,0.9),
(673,1.7),
(674,0.6),
(675,2.1),
(676,1.2),
(677,0.3),
(678,0.6),
(679,0.8),
(680,0.8),
(681,1.7),
(682,0.2),
(683,0.8),
(684,0.4),
(685,0.8),
(686,0.4),
(687,1.5),
(688,0.5),
(689,1.3),
(690,0.5),
(691,1.8),
(692,0.5),
(693,1.3),
(694,0.5),
(695,1),
(696,0.8),
(697,2.5),
(698,1.3),
(699,2.7),
(700,1),
(701,0.8),
(702,0.2),
(703,0.3),
(704,0.3),
(705,0.8),
(706,2),
(707,0.2),
(708,0.4),
(709,1.5),
(710,0.4),
(711,0.9),
(712,1),
(713,2),
(714,0.5),
(715,1.5),
(716,3),
(717,5.8),
(718,5),
(719,0.7),
(720,0.5),
(721,1.7),
(722,0.3),
(723,0.7),
(724,1.6),
(725,0.4),
(726,0.7),
(727,1.8),
(728,0.4),
(729,0.6),
(730,1.8),
(731,0.3),
(732,0.6),
(733,1.1),
(734,0.4),
(735,0.7),
(736,0.4),
(737,0.5),
(738,1.5),
(739,0.6),
(740,1.7),
(741,0.6),
(742,0.1),
(743,0.2),
(744,0.5),
(745,0.8),
(746,0.2),
(747,0.4),
(748,0.7),
(749,1),
(750,2.5),
(751,0.3),
(752,1.8),
(753,0.3),
(754,0.9),
(755,0.2),
(756,1),
(757,0.6),
(758,1.2),
(759,0.5),
(760,2.1),
(761,0.3),
(762,0.7),
(763,1.2),
(764,0.1),
(765,1.5),
(766,2),
(767,0.5),
(768,2),
(769,0.5),
(770,1.3),
(771,0.3),
(772,1.9),
(773,2.3),
(774,0.3),
(775,0.4),
(776,2),
(777,0.3),
(778,0.2),
(779,0.9),
(780,3),
(781,3.9),
(782,0.6),
(783,1.2),
(784,1.6),
(785,1.8),
(786,1.2),
(787,1.9),
(788,1.3),
(789,0.2),
(790,0.1),
(791,3.4),
(792,4),
(793,1.2),
(794,2.4),
(795,1.8),
(796,3.8),
(797,9.2),
(798,0.3),
(799,5.5),
(800,2.4),
(801,1),
(802,0.7),
(803,0.6),
(804,3.6),
(805,5.5),
(806,1.8),
(807,1.5),
(808,0.2),
(809,2.5),
(810,0.3),
(811,0.7),
(812,2.1),
(813,0.3),
(814,0.6),
(815,1.4),
(816,0.3),
(817,0.7),
(818,1.9),
(819,0.3),
(820,0.6),
(821,0.2),
(822,0.8),
(823,2.2),
(824,0.4),
(825,0.4),
(826,0.4),
(827,0.6),
(828,1.2),
(829,0.4),
(830,0.5),
(831,0.6),
(832,1.3),
(833,0.3),
(834,1),
(835,0.3),
(836,1),
(837,0.3),
(838,1.1),
(839,2.8),
(840,0.2),
(841,0.3),
(842,0.4),
(843,2.2),
(844,3.8),
(845,0.8),
(846,0.5),
(847,1.3),
(848,0.4),
(849,1.6),
(850,0.7),
(851,3),
(852,0.6),
(853,1.6),
(854,0.1),
(855,0.2),
(856,0.4),
(857,0.6),
(858,2.1),
(859,0.4),
(860,0.8),
(861,1.5),
(862,1.6),
(863,0.8),
(864,1),
(865,0.8),
(866,1.5),
(867,1.6),
(868,0.2),
(869,0.3),
(870,3),
(871,0.3),
(872,0.3),
(873,1.3),
(874,2.5),
(875,1.4),
(876,0.9),
(877,0.3),
(878,1.2),
(879,3),
(880,1.8),
(881,2.3),
(882,2.3),
(883,2),
(884,1.8),
(885,0.5),
(886,1.4),
(887,3),
(888,2.8),
(889,2.9),
(890,20),
(891,0.6),
(892,1.9),
(893,1.8),
(894,1.2),
(895,2.1),
(896,2.2),
(897,2),
(898,1.1),
(899,1.8),
(900,1.8),
(901,2.4),
(902,3),
(903,1.3),
(904,2.5),
(905,1.6),
(906,0.4),
(907,0.9),
(908,1.5),
(909,0.4),
(910,1),
(911,1.6),
(912,0.5),
(913,1.2),
(914,1.8),
(915,0.5),
(916,1),
(917,0.3),
(918,1),
(919,0.2),
(920,1),
(921,0.3),
(922,0.4),
(923,0.9),
(924,0.3),
(925,0.3),
(926,0.3),
(927,0.5),
(928,0.3),
(929,0.6),
(930,1.4),
(931,0.6),
(932,0.4),
(933,0.6),
(934,2.3),
(935,0.6),
(936,1.5),
(937,1.6),
(938,0.3),
(939,1.2),
(940,0.4),
(941,1.4),
(942,0.5),
(943,1.1),
(944,0.2),
(945,0.7),
(946,0.6),
(947,1.2),
(948,0.9),
(949,1.9),
(950,1.3),
(951,0.3),
(952,0.9),
(953,0.2),
(954,0.3),
(955,0.2),
(956,1.9),
(957,0.4),
(958,0.7),
(959,0.7),
(960,1.2),
(961,1.2),
(962,1.5),
(963,1.3),
(964,1.3),
(965,1),
(966,1.8),
(967,1.6),
(968,2.5),
(969,0.7),
(970,1.5),
(971,0.6),
(972,2),
(973,1.6),
(974,1.2),
(975,4.5),
(976,2.5),
(977,12),
(978,0.3),
(979,1.2),
(980,1.8),
(981,3.2),
(982,3.6),
(983,2),
(984,2.2),
(985,1.2),
(986,1.2),
(987,1.4),
(988,3.2),
(989,2.3),
(990,0.9),
(991,0.6),
(992,1.8),
(993,1.3),
(994,1.2),
(995,1.6),
(996,0.5),
(997,0.8),
(998,2.1),
(999,0.3),
(1000,1.2),
(1001,1.5),
(1002,1.9),
(1003,2.7),
(1004,0.4),
(1005,2),
(1006,1.4),
(1007,2.5),
(1008,3.5),
(1009,3.5),
(1010,1.5),
(1011,0.4),
(1012,0.1),
(1013,0.2),
(1014,1.8),
(1015,1),
(1016,1.4),
(1017,1.2),
(1018,2),
(1019,1.8),
(1020,3.5),
(1021,5.2),
(1022,1.5),
(1023,1.6),
(1024,0.2),
(1025,0.3)
) AS v(id, height)
WHERE pc.id = v.id;

-- ── Score d'une estimation : identique à sizeUpPoints (size-up-utils.ts) ────
CREATE OR REPLACE FUNCTION public.size_up_points(p_guess numeric, p_actual numeric) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT CASE
    WHEN p_guess IS NULL OR p_guess <= 0 OR p_actual IS NULL OR p_actual <= 0 THEN 0
    ELSE round((100 * greatest(0, 1 - abs(ln(p_guess::float8 / p_actual::float8)) / ln(5::float8)))::numeric)::integer
  END;
$$;

-- ── Paramètres et clé de classement : ajout du chrono de Size It Up ────────────
CREATE OR REPLACE FUNCTION public.solo_normalize_settings(p_mode text, p_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_gens int[];
  v_cats text[];
  v_hint text;
  v_timer int;
  v_result jsonb;
BEGIN
  SELECT coalesce(array_agg(DISTINCT g::int ORDER BY g::int), '{}')
    INTO v_gens
    FROM jsonb_array_elements_text(coalesce(p_settings->'generations', '[]'::jsonb)) AS g;
  SELECT coalesce(array_agg(DISTINCT c COLLATE "C" ORDER BY c COLLATE "C"), '{}')
    INTO v_cats
    FROM jsonb_array_elements_text(coalesce(p_settings->'categories', '[]'::jsonb)) AS c;
  IF EXISTS (SELECT 1 FROM unnest(v_gens) g WHERE g < 1 OR g > 9) THEN RAISE EXCEPTION 'invalid_settings'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_cats) c WHERE c NOT IN (
    'classique','starter','légendaire','fabuleux','fossile','ultra-chimère','pseudo-légendaire','bébé','paradoxe'
  )) THEN RAISE EXCEPTION 'invalid_settings'; END IF;

  v_result := jsonb_build_object('generations', to_jsonb(v_gens), 'categories', to_jsonb(v_cats));
  IF p_mode = 'who_that_pokemon' THEN
    v_hint := coalesce(p_settings->>'initialHint', 'silhouette');
    IF v_hint NOT IN ('silhouette','cry','pokedex_number','description','random') THEN RAISE EXCEPTION 'invalid_settings'; END IF;
    v_result := v_result || jsonb_build_object('initialHint', v_hint);
  END IF;
  IF p_mode = 'size_up' THEN
    v_timer := coalesce((p_settings->>'roundTimer')::int, 0);
    IF v_timer NOT IN (0, 15, 30, 60) THEN RAISE EXCEPTION 'invalid_settings'; END IF;
    v_result := v_result || jsonb_build_object('roundTimer', v_timer);
  END IF;
  RETURN v_result;
END; $$;

-- Doit rester identique à buildSettingsKey (leaderboard-utils.ts).
CREATE OR REPLACE FUNCTION public.solo_settings_key(p_mode text, p_settings jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT 'g=' || coalesce((SELECT string_agg(g, ',' ORDER BY g::int) FROM jsonb_array_elements_text(p_settings->'generations') g), '')
      || ';c=' || coalesce((SELECT string_agg(c, ',' ORDER BY c COLLATE "C") FROM jsonb_array_elements_text(p_settings->'categories') c), '')
      || CASE WHEN p_mode = 'who_that_pokemon' THEN ';h=' || coalesce(p_settings->>'initialHint', 'silhouette') ELSE '' END
      || CASE WHEN p_mode = 'size_up' THEN ';t=' || coalesce(p_settings->>'roundTimer', '0') ELSE '' END;
$$;

ALTER TABLE public.solo_scores DROP CONSTRAINT IF EXISTS solo_scores_mode_check;
ALTER TABLE public.solo_scores ADD CONSTRAINT solo_scores_mode_check
  CHECK (mode = ANY (ARRAY['stat_duel'::text, 'who_that_pokemon'::text, 'draft'::text, 'draft_trainer'::text, 'size_up'::text]));

-- ── Classement solo : score recalculé depuis le catalogue ───────────────────
CREATE OR REPLACE FUNCTION public.submit_size_up_score(p_run_id uuid, p_settings jsonb, p_rounds jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_settings jsonb := public.solo_normalize_settings('size_up', p_settings);
  v_ids int[];
  v_score numeric;
BEGIN
  IF jsonb_typeof(p_rounds) <> 'array' OR jsonb_array_length(p_rounds) <> 5 THEN RAISE EXCEPTION 'invalid_rounds'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_rounds) r
    WHERE (r->>'reference_id') IS NULL OR (r->>'target_id') IS NULL
       OR (r->>'reference_id')::int = (r->>'target_id')::int
       OR (jsonb_typeof(r->'guess') <> 'null' AND ((r->>'guess')::numeric < 0.05 OR (r->>'guess')::numeric > 30))
  ) THEN RAISE EXCEPTION 'invalid_rounds'; END IF;

  SELECT array_agg(id) INTO v_ids FROM (
    SELECT (r->>'reference_id')::int AS id FROM jsonb_array_elements(p_rounds) r
    UNION ALL
    SELECT (r->>'target_id')::int FROM jsonb_array_elements(p_rounds) r
  ) ids;
  IF NOT public.solo_pool_ok(v_ids, v_settings) THEN RAISE EXCEPTION 'invalid_rounds'; END IF;

  SELECT sum(public.size_up_points(nullif(r->>'guess', '')::numeric, pc.height))
    INTO v_score
    FROM jsonb_array_elements(p_rounds) r
    JOIN public.pokemon_catalog pc ON pc.id = (r->>'target_id')::int;

  RETURN public.record_solo_score(p_run_id, 'size_up', v_settings, public.solo_settings_key('size_up', v_settings),
    coalesce(v_score, 0), true, jsonb_build_object('rounds', p_rounds));
END; $$;

REVOKE ALL ON FUNCTION public.submit_size_up_score(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_size_up_score(uuid, jsonb, jsonb) TO authenticated;

-- ── Duo : rooms et estimations secrètes ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.size_up_rooms (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    player1_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    player2_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    status text DEFAULT 'waiting'::text NOT NULL,
    settings jsonb,
    round integer DEFAULT 1 NOT NULL,
    round_phase text DEFAULT 'guessing'::text NOT NULL,
    reference_pokemon_id integer,
    target_pokemon_id integer,
    used_pokemon_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    round_deadline timestamp with time zone,
    reveal_until timestamp with time zone,
    p1_submitted boolean DEFAULT false NOT NULL,
    p2_submitted boolean DEFAULT false NOT NULL,
    p1_score integer DEFAULT 0 NOT NULL,
    p2_score integer DEFAULT 0 NOT NULL,
    history jsonb DEFAULT '[]'::jsonb NOT NULL,
    winner text,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    CONSTRAINT size_up_rooms_status_check CHECK (status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text])),
    CONSTRAINT size_up_rooms_round_phase_check CHECK (round_phase = ANY (ARRAY['guessing'::text, 'reveal'::text])),
    CONSTRAINT size_up_rooms_winner_check CHECK (winner IS NULL OR winner = ANY (ARRAY['player1'::text, 'player2'::text, 'draw'::text]))
);
CREATE INDEX IF NOT EXISTS idx_size_up_rooms_created_at ON public.size_up_rooms USING btree (created_at);

DROP TRIGGER IF EXISTS size_up_rooms_bump_version ON public.size_up_rooms;
CREATE TRIGGER size_up_rooms_bump_version BEFORE UPDATE ON public.size_up_rooms
  FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();

-- Les estimations restent invisibles pour l'adversaire jusqu'à la révélation :
-- aucune policy, accès uniquement via les fonctions SECURITY DEFINER.
CREATE TABLE IF NOT EXISTS public.size_up_guesses (
    room_id uuid NOT NULL REFERENCES public.size_up_rooms(id) ON DELETE CASCADE,
    round integer NOT NULL,
    player_id uuid NOT NULL,
    guess numeric(7,3) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (room_id, round, player_id)
);
ALTER TABLE public.size_up_guesses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.size_up_guesses FROM anon, authenticated;

ALTER TABLE public.size_up_rooms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS size_up_rooms_select ON public.size_up_rooms;
CREATE POLICY size_up_rooms_select ON public.size_up_rooms FOR SELECT TO authenticated
  USING ((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::text));
DROP POLICY IF EXISTS size_up_rooms_insert ON public.size_up_rooms;
CREATE POLICY size_up_rooms_insert ON public.size_up_rooms FOR INSERT TO authenticated
  WITH CHECK ((auth.uid() = player1_id) AND status = 'waiting'::text AND player2_id IS NULL);
DROP POLICY IF EXISTS size_up_rooms_delete_owner ON public.size_up_rooms;
CREATE POLICY size_up_rooms_delete_owner ON public.size_up_rooms FOR DELETE TO authenticated
  USING (auth.uid() = player1_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'size_up_rooms'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.size_up_rooms;
  END IF;
END $$;

-- Invitations : autoriser le nouveau mode.
DROP POLICY IF EXISTS game_invites_insert ON public.game_invites;
CREATE POLICY game_invites_insert ON public.game_invites FOR INSERT TO authenticated
  WITH CHECK ((auth.uid() = sender_id) AND (status = 'pending'::text) AND (sender_id <> recipient_id)
    AND (game_mode = ANY (ARRAY['guess_my_pokemon'::text, 'stat_duel'::text, 'draft_duo'::text, 'who_that_pokemon'::text, 'pokemon_auction'::text, 'size_up'::text])));

-- Tire deux Pokémon distincts du pool, en évitant ceux déjà joués tant que possible.
CREATE OR REPLACE FUNCTION public.size_up_pick_pair(p_settings jsonb, p_used integer[]) RETURNS integer[]
    LANGUAGE sql VOLATILE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  WITH pool AS (
    SELECT pc.id FROM public.pokemon_catalog pc
    WHERE pc.height > 0
      AND (coalesce(jsonb_array_length(p_settings->'generations'), 0) = 0 OR p_settings->'generations' @> to_jsonb(pc.generation))
      AND (coalesce(jsonb_array_length(p_settings->'categories'), 0) = 0 OR p_settings->'categories' @> to_jsonb(pc.category))
  ), fresh AS (
    SELECT id FROM pool WHERE NOT (id = ANY (coalesce(p_used, '{}'::integer[])))
  )
  SELECT CASE WHEN (SELECT count(*) FROM fresh) >= 2
    THEN ARRAY(SELECT id FROM fresh ORDER BY random() LIMIT 2)
    ELSE ARRAY(SELECT id FROM pool ORDER BY random() LIMIT 2)
  END;
$$;

-- Deadline d'une manche : 1 s de marge pour l'affichage, NULL sans chrono.
CREATE OR REPLACE FUNCTION public.size_up_deadline(p_settings jsonb) RETURNS timestamp with time zone
    LANGUAGE sql VOLATILE
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT CASE WHEN coalesce((p_settings->>'roundTimer')::int, 0) > 0
    THEN clock_timestamp() + make_interval(secs => (p_settings->>'roundTimer')::int + 1)
    ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION public.join_size_up_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.size_up_rooms SET player2_id = v_user WHERE id = p_room_id;
END;
$$;

-- Paramètres (hôte, en attente), demande de revanche et abandon.
CREATE OR REPLACE FUNCTION public.update_size_up_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_bad_keys text[];
  v_abandon boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','winner','p1_ready','p2_ready']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF p_patch ? 'status' AND p_patch->>'status' IS DISTINCT FROM 'finished' THEN RAISE EXCEPTION 'forbidden_status'; END IF;
  IF p_patch ? 'winner' AND jsonb_typeof(p_patch->'winner') <> 'null' THEN RAISE EXCEPTION 'forbidden_winner'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND (v_user <> v_room.player1_id OR v_room.status <> 'finished') THEN RAISE EXCEPTION 'forbidden_ready'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND (v_user IS DISTINCT FROM v_room.player2_id OR v_room.status <> 'finished') THEN RAISE EXCEPTION 'forbidden_ready'; END IF;

  -- Abandon : la room est close sans vainqueur.
  v_abandon := p_patch ? 'status';

  UPDATE public.size_up_rooms
  SET
    status = CASE WHEN v_abandon THEN 'finished' ELSE status END,
    winner = CASE WHEN v_abandon THEN NULL ELSE winner END,
    round_deadline = CASE WHEN v_abandon THEN NULL ELSE round_deadline END,
    reveal_until = CASE WHEN v_abandon THEN NULL ELSE reveal_until END,
    settings = CASE WHEN p_patch ? 'settings' THEN public.solo_normalize_settings('size_up', p_patch->'settings') ELSE settings END,
    p1_ready = CASE WHEN v_abandon THEN false WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN v_abandon THEN false WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END
  WHERE id = p_room_id;
END;
$$;

-- Lancement et revanche : le serveur tire la première paire.
CREATE OR REPLACE FUNCTION public.start_size_up_game(p_room_id uuid, p_settings jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_settings jsonb;
  v_pair integer[];
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'not_host'; END IF;
  IF v_room.player2_id IS NULL THEN RAISE EXCEPTION 'missing_opponent'; END IF;
  IF NOT (v_room.status = 'waiting' OR (v_room.status = 'finished' AND v_room.p1_ready AND v_room.p2_ready)) THEN
    RAISE EXCEPTION 'room_not_startable';
  END IF;

  -- Revanche : on garde les paramètres de la partie précédente.
  v_settings := public.solo_normalize_settings('size_up',
    CASE WHEN v_room.status = 'finished' AND v_room.settings IS NOT NULL THEN v_room.settings ELSE p_settings END);
  v_pair := public.size_up_pick_pair(v_settings, '{}'::integer[]);
  IF coalesce(array_length(v_pair, 1), 0) < 2 THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;

  DELETE FROM public.size_up_guesses WHERE room_id = p_room_id;
  UPDATE public.size_up_rooms SET
    status = 'playing', settings = v_settings, round = 1, round_phase = 'guessing',
    reference_pokemon_id = v_pair[1], target_pokemon_id = v_pair[2], used_pokemon_ids = v_pair,
    round_deadline = public.size_up_deadline(v_settings), reveal_until = NULL,
    p1_submitted = false, p2_submitted = false, p1_score = 0, p2_score = 0, history = '[]'::jsonb,
    winner = NULL, p1_ready = false, p2_ready = false
  WHERE id = p_room_id;
END;
$$;

-- Révèle la manche courante (room déjà verrouillée par l'appelant) : points, historique, scores.
CREATE OR REPLACE FUNCTION public.size_up_reveal_round(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_room public.size_up_rooms;
  v_actual numeric;
  v_p1_guess numeric;
  v_p2_guess numeric;
  v_p1_points integer;
  v_p2_points integer;
BEGIN
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id;
  SELECT height INTO v_actual FROM public.pokemon_catalog WHERE id = v_room.target_pokemon_id;
  SELECT guess INTO v_p1_guess FROM public.size_up_guesses WHERE room_id = p_room_id AND round = v_room.round AND player_id = v_room.player1_id;
  SELECT guess INTO v_p2_guess FROM public.size_up_guesses WHERE room_id = p_room_id AND round = v_room.round AND player_id = v_room.player2_id;
  v_p1_points := public.size_up_points(v_p1_guess, v_actual);
  v_p2_points := public.size_up_points(v_p2_guess, v_actual);

  UPDATE public.size_up_rooms SET
    round_phase = 'reveal',
    round_deadline = NULL,
    reveal_until = clock_timestamp() + interval '6 seconds',
    p1_score = p1_score + v_p1_points,
    p2_score = p2_score + v_p2_points,
    history = history || jsonb_build_array(jsonb_build_object(
      'round', v_room.round,
      'reference_id', v_room.reference_pokemon_id,
      'target_id', v_room.target_pokemon_id,
      'p1_guess', v_p1_guess,
      'p2_guess', v_p2_guess,
      'p1_points', v_p1_points,
      'p2_points', v_p2_points
    ))
  WHERE id = p_room_id;
END;
$$;
REVOKE ALL ON FUNCTION public.size_up_reveal_round(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_size_up_guess(p_room_id uuid, p_round integer, p_guess numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_is_p1 boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_guess IS NULL OR p_guess < 0.05 OR p_guess > 30 THEN RAISE EXCEPTION 'invalid_guess'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF v_room.round <> p_round THEN RAISE EXCEPTION 'stale_round'; END IF;
  IF v_room.round_phase <> 'guessing'
     OR (v_room.round_deadline IS NOT NULL AND clock_timestamp() > v_room.round_deadline + interval '2 seconds') THEN
    RAISE EXCEPTION 'round_closed';
  END IF;

  IF v_user = v_room.player1_id THEN
    v_is_p1 := true;
    IF v_room.p1_submitted THEN RAISE EXCEPTION 'already_submitted'; END IF;
  ELSIF v_user = v_room.player2_id THEN
    v_is_p1 := false;
    IF v_room.p2_submitted THEN RAISE EXCEPTION 'already_submitted'; END IF;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;

  INSERT INTO public.size_up_guesses (room_id, round, player_id, guess) VALUES (p_room_id, p_round, v_user, round(p_guess, 3));
  UPDATE public.size_up_rooms SET
    p1_submitted = p1_submitted OR v_is_p1,
    p2_submitted = p2_submitted OR NOT v_is_p1
  WHERE id = p_room_id
  RETURNING * INTO v_room;

  IF v_room.p1_submitted AND v_room.p2_submitted THEN
    PERFORM public.size_up_reveal_round(p_room_id);
  END IF;
END;
$$;

-- Fait avancer la manche quand un délai est écoulé ; sans effet sinon (appelable par les deux clients).
CREATE OR REPLACE FUNCTION public.finalize_size_up_round(p_room_id uuid, p_round integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_pair integer[];
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status <> 'playing' OR v_room.round <> p_round THEN RETURN; END IF;

  IF v_room.round_phase = 'guessing' THEN
    IF v_room.round_deadline IS NOT NULL AND clock_timestamp() >= v_room.round_deadline + interval '2 seconds' THEN
      PERFORM public.size_up_reveal_round(p_room_id);
    END IF;
    RETURN;
  END IF;

  IF v_room.reveal_until IS NULL OR clock_timestamp() < v_room.reveal_until THEN RETURN; END IF;

  IF v_room.round >= 5 THEN
    UPDATE public.size_up_rooms SET
      status = 'finished', round_deadline = NULL, reveal_until = NULL,
      winner = CASE WHEN p1_score > p2_score THEN 'player1' WHEN p2_score > p1_score THEN 'player2' ELSE 'draw' END,
      p1_ready = false, p2_ready = false
    WHERE id = p_room_id;
    DELETE FROM public.size_up_guesses WHERE room_id = p_room_id;
    RETURN;
  END IF;

  v_pair := public.size_up_pick_pair(v_room.settings, v_room.used_pokemon_ids);
  IF coalesce(array_length(v_pair, 1), 0) < 2 THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;
  UPDATE public.size_up_rooms SET
    round = round + 1, round_phase = 'guessing',
    reference_pokemon_id = v_pair[1], target_pokemon_id = v_pair[2],
    used_pokemon_ids = used_pokemon_ids || v_pair,
    round_deadline = public.size_up_deadline(settings), reveal_until = NULL,
    p1_submitted = false, p2_submitted = false
  WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_old_size_up_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.size_up_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;

DO $$
BEGIN
  -- Imbriqué : cron.job n'est résolu que si l'extension est présente.
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'delete-old-size-up-rooms') THEN
      PERFORM cron.schedule('delete-old-size-up-rooms', '0 * * * *', 'SELECT public.delete_old_size_up_rooms();');
    END IF;
  END IF;
END $$;
